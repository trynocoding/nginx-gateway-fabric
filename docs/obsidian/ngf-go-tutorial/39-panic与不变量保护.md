---
title: "39 panic 作为程序员错误和不变量保护"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 39 panic 作为程序员错误和不变量保护

> [!abstract]
> panic 用于“按程序结构本不可能发生”的状态：错误注册、类型接线、穷举分支遗漏等。文件权限、网络、用户配置等运行失败必须返回 error。recover 只应放在能恢复一致性并定义失败隔离的边界。

## 学习目标与前置

- 理解 panic 时 defer 的执行和 goroutine 边界；
- 区分程序员错误、内部不变量与可预期运行错误；
- 谨慎使用 `MustX` 和 recover；
- 追踪 NGF 动态对象构造、类型断言与 File.Type 的 panic 防线。

前置：[[20-defer与资源清理]]、[[28-构造函数与不变量]]、[[36-错误链与百分号w]]。

## 1. panic 的运行模型

调用 `panic(v)` 后，当前函数停止正常执行，按后进先出执行已注册 defer，然后逐层展开调用栈。若直到该 goroutine 栈顶都未 recover，程序崩溃并打印栈。

```go
func f() {
	defer cleanup()
	panic("broken invariant")
}
```

recover 只有在 defer 调用链中直接生效：

```go
defer func() {
	if v := recover(); v != nil {
		// 转换、记录或隔离
	}
}()
```

一个 goroutine 不能从另一个 goroutine recover panic。若 worker 需要隔离，recover 必须位于该 worker 自己的顶层，并确保状态未被半写入。

## 2. 可独立运行的最小 demo

**可运行 demo（Go 1.26.0，保存为 `main.go`）：**

```go
package main

import (
	"fmt"
	"strconv"
)

func parsePort(raw string) (int, error) {
	port, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("parse port %q: %w", raw, err)
	}
	return port, nil
}

func mustAt[T any](items []T, index int) T {
	if index < 0 || index >= len(items) {
		panic(fmt.Sprintf("index %d outside registered range", index))
	}
	return items[index]
}

func runTask() (err error) {
	defer func() {
		if v := recover(); v != nil {
			err = fmt.Errorf("task invariant failed: %v", v)
		}
	}()
	_ = mustAt([]string{"gateway"}, 3)
	return nil
}

func main() {
	_, inputErr := parsePort("not-a-port")
	fmt.Println(inputErr != nil)
	fmt.Println(runTask())
}
```

验证：

```bash
gofmt -w main.go
go run main.go
# true
# task invariant failed: index 3 outside registered range
```

demo 展示边界，不表示所有 panic 都应 recover。`runTask` 能恢复，是因为它定义了独立任务失败的转换点；真实服务还必须保证没有泄漏锁、半提交状态或继续使用损坏对象。

## 3. 四种常用模式

### 3.1 `MustX` 构造/解析

模板、正则或静态配置在程序启动时由开发者提供，失败意味着构建/接线错误，可用 `template.Must` 风格。动态用户输入不可用 Must。

### 3.2 穷举内部枚举

switch 已覆盖所有已注册常量，default panic 能在新增枚举而忘记同步消费者时立刻暴露问题。

### 3.3 类型接线断言

registry 已保证 GVK→具体对象类型，后续断言失败意味着内部映射损坏；panic 比继续写错 store 更安全。

### 3.4 框架隔离边界 recover

服务器/任务框架有时在请求或 worker 顶层 recover，记录栈并隔离单个任务。业务深层不应随意 recover 后假装成功。

## 4. NGF：反射对象构造的不变量

`internal/framework/controller/reconciler.go:Reconciler.mustCreateNewObject` 从注册时的 `ObjectType` prototype 取运行时类型并创建新对象：

```go
t := reflect.TypeOf(objectType).Elem()
obj, ok := reflect.New(t).Interface().(client.Object)
if !ok {
	panic("failed to create a new object")
}
```

调用关系：controller 注册保证 ObjectType → controller-runtime 调 Reconcile → 动态创建同类零值 → Getter 填充 → 发 Upsert/Delete event。若新值不实现 `client.Object`，说明注册配置与 Reconciler 合同矛盾，不是 Kubernetes 用户可修复的输入错误，所以 fail-fast。

附近的 `reconciler_test.go` 覆盖正常具体对象创建后的 upsert/delete、过滤、API error 和 context cancel；当前私有失败断言没有独立测试，属于可补强点，不应虚构已覆盖。

## 5. NGF 的其他 panic 边界

### `helpers.MustCastObject`

状态 setter 已与某个资源类型绑定，收到另一动态类型会 panic。`helpers_test.go:TestMustCastObject` 明确覆盖成功和错误类型。

### `file.ensureType`

`TypeRegular`/`TypeSecret` 是内部枚举；未知值在执行任何文件副作用前 panic。`file_test.go` 的 `file type is not supported` 验证该分支。与之相对，Create/Chmod/Write 失败均返回 error，因为它们是运行环境失败。

### `PrepareTimeForFakeClient` 与 `MustExecuteTemplate`

二者面向测试/静态模板辅助：无法 marshal/unmarshal 或模板执行失败被视为调用者错误。`helpers_test.go:TestMustExecuteTemplatePanics` 覆盖 nil template。

## 6. panic 适用性矩阵

| 失败 | 应对 | 理由 |
|---|---|---|
| 用户端口格式错误 | error | 可预期、可提示修正 |
| 网络/磁盘失败 | error | 环境可恢复或重试 |
| context canceled | error/正常退出 | 生命周期信号 |
| registry 类型映射矛盾 | panic | 程序员/接线错误 |
| 未知内部枚举 | panic | 穷举不变量破坏 |
| 外部协议出现新枚举 | 通常 error | 版本偏差可在边界处理 |

关键问题不是“严重不严重”，而是“调用者能否在正常控制流中合理恢复”。

## 7. recover 的误区与迁移边界

- recover 后不记录栈会丢失最重要诊断信息；生产边界通常需要 `debug.Stack()`。
- recover 后继续使用可能半修改的对象会扩大损坏。
- 不要用 panic/recover 模拟普通异常控制流，代码路径和测试都会更难推理。
- `panic(error)` 不等于返回 error；只有 recover 后显式转换才重新进入 error 控制流。
- 库函数若对外部输入 panic，会把恢复责任强加给所有调用者。

迁移边界：若 `ObjectType` 未来来自开放插件或不受信任扩展，类型不匹配就不再是纯内部不变量，注册 API 应在启动阶段返回 error，并阻止 controller 启动；不能只在 panic 外包一层 recover。

## 8. 练习与答案

1. 删除 demo 的 recover，观察 defer 和进程结果。
2. 为 `mustAt` 写表驱动测试，覆盖合法、负数、越界。
3. 把 `file.ensureType` 改为返回 error 会影响哪些调用和测试？

检查点：合法 case 断言返回值；非法 case 用 `defer recover` 或测试框架的 Panic matcher。第 3 题至少要同步 `Write` 的签名/早退、unsupported type 测试和所有依赖 panic 不变量的调用者；若 File.Type 可来自外部转换，还要明确未知权限的校验位置。

## 源码证据索引

| 主题 | 证据 |
|---|---|
| 反射构造防线 | `ngf:internal/framework/controller/reconciler.go:Reconciler.mustCreateNewObject` |
| 正常调用路径测试 | `ngf:internal/framework/controller/reconciler_test.go` |
| 泛型类型断言 panic | `ngf:internal/framework/helpers/helpers.go:MustCastObject`；`helpers_test.go:TestMustCastObject` |
| 内部枚举保护 | `ngf:internal/framework/file/file.go:ensureType`；`file_test.go` unsupported type case |
| Must helper | `ngf:internal/framework/helpers/helpers.go:PrepareTimeForFakeClient,MustExecuteTemplate` |

下一步：[[40-goroutine启动与退出责任]]、[[54-reflect与运行时类型注册]]。
