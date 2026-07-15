---
title: "11 append、容量与预分配"
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

# 11 append、容量与预分配

> [!abstract]
> slice 的长度是可见元素数，容量是从起点到底层数组末端可扩展的空间。`append` 必须接住返回值，因为它可能复用原数组，也可能分配新数组。预分配的关键是分清 `make([]T, n)` 与 `make([]T, 0, n)`。

## 学习目标与前置

- 使用 `len`、`cap`、`make`、`append`；
- 解释 append 何时可能换底层数组；
- 根据“按索引填写”或“逐个追加”选择预分配形式；
- 看懂 NGF EventLoop 为何复用两个 batch slice。

前置：[[10-数组与切片的类型差异]]。

## 1. slice header 的心智模型

可以把 slice 想成三元组：底层数组指针、长度、容量。该模型用于推理，不是要求依赖运行时内部布局。

```go
a := make([]int, 3)    // len=3 cap=3，已有三个 0
b := make([]int, 0, 3) // len=0 cap=3，没有可索引元素
```

`a[0] = 1` 合法；`b[0] = 1` 越界。对 b 应写 `b = append(b, 1)`。

### append 必须接返回值

```go
s = append(s, value)
s = append(s, more...)
```

容量足够时，append 可写入原底层数组并返回更长 header；不足时分配更大数组、复制旧元素再追加。扩容倍率是实现细节，不要在业务逻辑中假定“总是翻倍”。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import "fmt"

func main() {
	ports := make([]int, 0, 2)
	fmt.Printf("start len=%d cap=%d\n", len(ports), cap(ports))

	for _, p := range []int{80, 443, 8080} {
		ports = append(ports, p)
		fmt.Printf("append %d: len=%d cap=%d values=%v\n",
			p, len(ports), cap(ports), ports)
	}

	wrong := make([]int, 2)
	wrong = append(wrong, 80)
	fmt.Println("wrong", wrong)
}
```

```bash
gofmt -w main.go
go run main.go
```

稳定结论是前三次长度依次为 1、2、3，`wrong` 为 `[0 0 80]`。具体扩容后的 cap 不应写进测试，因为属于实现策略。

## 3. 常用模式

### 3.1 已知最终长度：分配 len 后按索引写

```go
out := make([]Result, len(in))
for i, v := range in {
	out[i] = convert(v)
}
```

适合一对一转换，不需要 append。

### 3.2 已知最大/预计数量：len 0 + cap

```go
out := make([]Result, 0, len(in))
for _, v := range in {
	if keep(v) {
		out = append(out, convert(v))
	}
}
```

适合过滤或一对多，避免先制造零值元素。

### 3.3 拼接多个 slice

先计算总长度/容量，再 `append(dst, src...)`。注意元素若含指针仍共享指向对象。

### 3.4 复用容量降低批处理分配

处理完写 `s = s[:0]` 清空长度但保留容量。若元素含大对象指针且 slice 长期存活，可能需要 `clear(s)` 解除引用，避免延长对象生命周期。

## 4. NGF：EventLoop 的双缓冲 batch

焦点：`ngf:internal/framework/events/loop.go:EventLoop` 与 `EventLoop.Start`。

构造函数初始化两个空 batch：

```go
// NGF 缩写源码，不是独立 demo
currentBatch: make(EventBatch, 0),
nextBatch:    make(EventBatch, 0),
```

运行时收到事件：

```go
el.nextBatch = append(el.nextBatch, e)
```

当前 batch 由 handler goroutine 读取时，新事件只追加到 nextBatch。处理完成后 `swapBatches`：

```go
el.currentBatch, el.nextBatch = el.nextBatch, el.currentBatch
el.nextBatch = el.nextBatch[:0]
```

数据/所有权关系：

```text
eventCh → append(nextBatch)
               │ 当前 handler 完成
               ▼
swap current/next → handler 只读 currentBatch
               └→ 旧 current 截成 len=0，作为新 next 复用容量
```

这里复用的前提是不同时写 handler 正在读取的底层区域。交换后两个 slice 原本来自两块不同缓冲；事件循环单 goroutine 拥有 slice header，并且一次最多处理一个 batch。`internal/framework/events/loop_test.go` 覆盖首批、处理期间积累、取消等待等行为。

### 为什么没有预设 cap

事件量难准确预测；空 slice 让运行时按实际负载增长。处理过大 burst 后保留容量可能增加常驻内存，这是复用与释放之间的取舍。当前源码没有容量上限或缩容策略，不应声称它能限制内存。

## 5. 边界与误区

- 忘记 `s = append(s, x)` 会丢失新 header；有时底层被写但 len 未变，行为更迷惑；
- `make([]T, n)` 后再 append 会把值放在 n 个零值之后；
- cap 预分配是性能优化，不应替代正确性；先用 profile/benchmark 判断；
- `s[:0]` 不清除底层引用；长寿命缓存可能需要 clear 或丢弃大数组；
- append 后旧 slice 和新 slice 是否共享不能一概而论，取决于是否扩容。

## 6. 迁移判断

- **直接复用**：一对一用 len，过滤用 len0/cap；始终接 append 返回值。
- **条件复用**：双缓冲容量复用，需要单一所有者和清晰的读写阶段。
- **不可照搬**：在无界输入上永久保留峰值容量，或依赖具体扩容倍数。

## 7. 练习与答案

1. `make([]int, 3, 10)` 后 append 一个值，长度多少？4，前三个元素已经存在且为零。
2. 过滤最多保留 n 个元素如何分配？`make([]T, 0, n)`。
3. `s = s[:0]` 是否释放数组？不保证；通常保留数组和容量。
4. EventLoop 为什么不能把 currentBatch 截零后立即用于接收？handler 仍在读取它，会发生数据竞争/内容破坏；必须交换独立 batch。

## 源码证据索引

- `ngf:internal/framework/events/loop.go:EventLoop`、`NewEventLoop`。
- `ngf:internal/framework/events/loop.go:EventLoop.Start`（append）。
- `ngf:internal/framework/events/loop.go:EventLoop.swapBatches`（交换与复用）。
- `ngf:internal/framework/events/loop_test.go`。

上一章：[[10-数组与切片的类型差异]] · 下一章：[[12-切片共享与防御性复制]] · 延伸：[[49-EventLoop批处理与状态所有权]]
