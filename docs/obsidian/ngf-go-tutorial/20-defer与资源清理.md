---
title: "20 defer 与资源清理"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 20 defer 与资源清理

> [!abstract] 核心结论
> `defer` 在当前函数返回前执行调用，适合把 acquire/release 写在一起。参数在注册 defer 时求值，多个 defer 后进先出；函数值本身延后执行。它覆盖正常返回和 panic 展开，但不覆盖进程被强制终止。

## 学习目标与前置

前置：[[19-函数值闭包与高阶函数]]、理解函数返回。完成后应能：

- 解释 defer 的注册时机、参数求值、LIFO 顺序；
- 用它关闭资源、取消 context、解锁和记录耗时；
- 避免在长循环中无界积累 defer；
- 读懂 NGF 在 S3 body、锁和事件批处理三个不同生命周期里的用法。

## 1. 精确语义

```go
defer f(x)
```

执行到这行时就计算 `f` 和 `x`，但真正调用在当前函数即将返回时。闭包有所不同：

```go
defer func() { fmt.Println(x) }()
```

闭包体返回前才读 `x`，所以可能看到之后的修改。多个 defer 按栈顺序执行，最后注册的最先运行。

## 2. 可独立运行的最小 demo

**可运行示例（Go 1.26.0，标准库）：**

```go
package main

import (
	"fmt"
	"strings"
)

func read() (result string) {
	body := strings.NewReader("gateway")
	fmt.Println("acquire", body.Len())
	defer fmt.Println("cleanup-argument", body.Len())
	defer func() {
		fmt.Println("cleanup-closure", body.Len())
	}()

	buf := make([]byte, 4)
	_, _ = body.Read(buf)
	return string(buf)
}

func main() {
	fmt.Println("result", read())
}
```

运行后先打印 acquire；返回前先执行闭包（观察剩余 3），再执行较早注册的 defer（参数早已固定为 7），最后 main 打印结果。已在 `go1.26.0` 下执行验证。

## 3. 四种常用模式

### 模式一：资源关闭

成功获得 `io.Closer` 后立刻 `defer Close()`，确保后续任一 return 都清理。若 Close 的错误会影响正确性（例如写文件 flush），不能简单丢弃，应在显式关闭或命名 error 中合并。

### 模式二：context cancel

`ctx, cancel := context.WithTimeout(...); defer cancel()` 释放 timer 和下游引用。取消应紧跟创建，避免新增 return 时漏清理。

### 模式三：锁成对

```go
mu.Lock()
defer mu.Unlock()
```

适合短临界区。若函数剩余逻辑很长，defer 会把锁持有到函数末尾，应缩小辅助函数或显式解锁。

### 模式四：收尾观测

入口记录 `start := time.Now()`，deferred closure 在所有返回路径记录耗时。闭包也能读取最终命名结果，但这会增加隐式控制流。

## 4. NGF 生产实例

### 4.1 S3 response body

`internal/framework/waf/fetch/s3/s3.go:(*Fetcher).FetchBundle` 在 `GetObject` 成功后立即：

```go
defer result.Body.Close()
```

**生产源码节选。** 注册点在确认 body 存在之后；后面的 `io.ReadAll`、checksum 校验和所有失败 return 都经过 Close。当前代码忽略 Close error，适用于只读 response body：主要业务结果已由读取/校验决定。

### 4.2 context timeout

`internal/framework/controller/register.go:AddIndex` 用 `context.WithTimeout` 创建子 context，并立即 `defer cancel()`，然后调用 `Indexer.IndexField`。不论索引成功还是返回错误，timer 都会释放。

### 4.3 锁与观测

`internal/controller/nginx/agent/broadcast/broadcast.go:(*DeploymentBroadcaster).Send` 在 `RLock` 后 defer `RUnlock`；`internal/controller/handler.go:(*eventHandlerImpl).HandleEventBatch` 用 deferred closure 记录整个 batch 耗时并上报 metric。

三者共同点是“清理属于当前函数的词法生命周期”，但资源类型、失败语义完全不同，不能只机械记 `defer`。

## 5. 测试证据与未覆盖边界

- `internal/framework/controller/register_test.go` 覆盖 `AddIndex` 成功与 `IndexField` 返回错误的路径，证明两类
  return 都能完成；它没有直接观测 timeout timer 是否释放，因此 timer 清理仍主要由源码中的 `defer cancel()` 证明。
- `internal/controller/nginx/agent/broadcast/broadcast_test.go` 覆盖 `Send` 的正常握手、父 context 取消和订阅取消，
  能间接发现锁未释放造成的阻塞；测试没有直接断言 `RUnlock` 调用次数。
- `internal/controller/handler_test.go` 让 `HandleEventBatch` 经过单事件、多事件和多个失败分支，约束 deferred
  收尾不能破坏返回路径；当前注入的是 noop metrics collector，没有直接断言耗时观测值。
- `internal/framework/waf/fetch/s3/s3_test.go` 当前覆盖 URI 解析与 TLS transport，但没有用可观测 `ReadCloser`
  直接证明 `FetchBundle` 在每条读取/校验路径都会关闭 response body。这是本章找到的测试缺口，不应把“附近有测试”
  写成 Close 行为已有测试保证。

## 6. 循环、panic 与进程边界

> [!warning] defer 绑定到函数，不是循环迭代
> 在处理海量元素的同一个函数里每轮 defer Close，会直到整个函数返回才释放。把单次处理抽成辅助函数，或在每轮末尾显式关闭。

- defer 会在 panic 的栈展开中执行，但 `os.Exit`、fatal signal、机器掉电不会保证执行；
- defer 内再 panic 可能掩盖原 panic；
- `recover` 只有在 deferred function 中直接调用才有意义，详见 [[39-panic与不变量保护]]；
- 注册 defer 前若 acquire 已失败，不能对 nil 资源调用 Close。

## 7. 迁移边界

**可直接迁移：** 成功 acquire 后立即 defer release；WithCancel 后 defer cancel。**有条件迁移：** defer Unlock，只适合临界区覆盖整个余下函数。**不可照搬：** 忽略所有 Close error；写入型资源可能必须检查它。

## 8. 练习与验证

1. 交换 demo 两个 defer 的顺序，预测输出后再运行。检查 LIFO。
2. 写 `for` 循环，每次调用辅助函数，辅助函数内 defer 打印。检查每轮结束就打印，而不是循环结束统一打印。
3. 给一个返回 `(err error)` 的函数加 deferred cleanup，并在 cleanup 失败时 `errors.Join(err, cleanupErr)`。检查原错误和清理错误都可被 `errors.Is` 识别。

## 源码证据索引与下一步

| 用途 | 证据 |
|---|---|
| 关闭只读响应体 | `internal/framework/waf/fetch/s3/s3.go:(*Fetcher).FetchBundle` |
| 释放 timeout context | `internal/framework/controller/register.go:AddIndex` |
| 读锁释放 | `internal/controller/nginx/agent/broadcast/broadcast.go:(*DeploymentBroadcaster).Send` |
| 全路径耗时观测 | `internal/controller/handler.go:(*eventHandlerImpl).HandleEventBatch` |
| timeout 路径测试 | `internal/framework/controller/register_test.go` |
| 广播取消/握手测试 | `internal/controller/nginx/agent/broadcast/broadcast_test.go` |
| batch 多分支测试 | `internal/controller/handler_test.go` |
| S3 邻近测试与 Close 缺口 | `internal/framework/waf/fetch/s3/s3_test.go` |

上一章：[[19-函数值闭包与高阶函数]] · 下一章：[[21-方法与接收者]] · 并发深化：[[46-Mutex-RWMutex与临界区]]
