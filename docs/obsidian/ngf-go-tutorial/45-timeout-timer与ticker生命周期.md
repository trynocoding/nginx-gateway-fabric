---
title: "45 timeout、timer 与 ticker 生命周期"
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

# 45 timeout、timer 与 ticker 生命周期

> [!abstract]
> timeout 是一次操作的时间预算，Timer 是一次触发对象，Ticker 是周期触发对象。创建者必须定义停止、重置、取消竞争和回调完成语义。Go 1.23+ 改变了 timer channel 与 GC 保证，旧的“Stop 后必须 drain”口诀不能无版本照搬。

## 学习目标与前置

- 区分 `Sleep`、`After`、`NewTimer`、`AfterFunc`、`NewTicker`；
- 掌握 Go 1.26 的 `Stop`、`Reset`、channel/drain 语义；
- 为一次超时、周期任务、debounce 和回调选择模式；
- 追踪 NGF WAF poller 与 TLS FileWatcher 的 ticker 生命周期。

前置：[[43-select多路复用]]、[[44-context传递与取消]]。

## 1. API 与心智模型

**Go 1.26 API 说明性示例：**

```go
time.Sleep(d)              // 当前 goroutine 至少暂停 d
time.After(d)              // 返回 <-chan time.Time，一次触发
timer := time.NewTimer(d)  // 可 Stop/Reset 的一次 timer
timer := time.AfterFunc(d, f) // 到时在自己的 goroutine 调 f；C 为 nil
ticker := time.NewTicker(d)   // 周期 tick；d<=0 panic
```

timeout 是产品/调用合同；timer 是实现它的一种机制。若下游 API 接受 context，优先 `context.WithTimeout` 让整个调用树共享预算，而不是只在外层 select timer、留下内部 I/O 继续运行。

## 2. Go 1.26 Timer 精确语义

### `NewTimer` 与 channel

Go 1.23 起，`NewTimer` 的 `C` 是同步、无缓冲 channel（`cap==0`）。未引用且未 stop 的 timer 可被 GC 回收。GC 改进不等于“不需 Stop”：仍在作用域内但不再需要时 Stop 能及时阻止触发，表达所有权。

### `Timer.Stop() bool`

- channel-based timer：Go 1.23+ 中 Stop 返回后，后续 receive 保证不会收到 Stop 前的 stale time；
- 若 timer 尚未到期且值未被接收，Stop 保证返回 true；
- func-based timer：false 可能表示回调已经开始；Stop 不等待回调完成；
- Stop 不关闭 `C`，因此 `for range timer.C` 不会因 Stop 退出。

### `Timer.Reset(d) bool`

channel-based timer 在 Go 1.23+ 可直接 Reset：Reset 返回后不会收到旧配置的 stale time；无需先 Stop+drain。返回 true 表示原 timer active。

`AfterFunc` timer 的 Reset 不同：active 时改期返回 true；已触发/停止后返回 false 并安排再次执行，且不等待旧回调结束，因此两次 `f` 可能并发。

### 旧 drain 口诀的版本边界

Go 1.22 及更早，安全 Stop/Reset 常需在 Stop=false 时条件 drain `C`，避免旧缓冲值。Go 1.26 不需要且不应盲目执行：同步 channel 上无发送者时 `<-timer.C` 会死锁。

> [!danger]
> 不要复制无版本的 `if !timer.Stop() { <-timer.C }`。它是旧版本兼容模式，不是 Go 1.26 的通用模板。

## 3. Ticker 精确语义

`NewTicker(d)` 周期发送时间；接收者慢时 ticker 会调整间隔或丢 tick 以追赶，不保证逐 tick 排队。`Stop` 停止后续 tick，但不关闭 `C`，避免并发接收者把关闭误当 tick。

Go 1.23+ GC 可回收不可达 ticker，所以 Stop 不再是为了 GC 的硬性要求；但明确生命周期仍应 `defer ticker.Stop()`，及时停止无用工作并让代码审查者看到所有权。`Reset(d)` 改周期，`d<=0` panic。

`time.Tick(d)` 只返回 channel，无法显式 Stop；Go 1.23+ 不再因 GC 造成永久资源保留，但需要生命周期控制时仍用 `NewTicker`。

## 4. 可独立运行 demo：可重置 idle timeout

```go
package main

import (
	"fmt"
	"time"
)

func consume(events <-chan string, idle time.Duration) {
	timer := time.NewTimer(idle)
	defer timer.Stop()
	for {
		select {
		case event, ok := <-events:
			if !ok {
				fmt.Println("closed")
				return
			}
			fmt.Println(event)
			timer.Reset(idle) // Go 1.26：无需 Stop+drain
		case <-timer.C:
			fmt.Println("idle timeout")
			return
		}
	}
}

func main() {
	events := make(chan string)
	go func() {
		events <- "a"
		time.Sleep(5 * time.Millisecond)
		events <- "b"
	}()
	consume(events, 20*time.Millisecond)
}
```

```bash
gofmt -w main.go && go run main.go
# a
# b
# idle timeout
```

失败路径是生产者不再发送且不 close；timer 让 consumer 有界退出。生产代码通常还要加 `ctx.Done()`，让 shutdown 不必等待 idle timeout。

## 5. 常用模式

### 一次操作 timeout

**说明性示例：**

```go
ctx, cancel := context.WithTimeout(parent, 500*time.Millisecond)
defer cancel()
return client.Call(ctx)
```

可传播到下游，优于只包住结果 channel。

### select 一次等待

`timer := time.NewTimer(d); defer timer.Stop()`，在 result、timer.C、ctx.Done 间 select。若 ctx 已有 deadline，通常无需再建重复 timer。

### 周期任务立即执行再 tick

许多 poller 应启动即执行一次，然后 `NewTicker` 做后续周期；若只等第一个 tick，会无谓延迟一个 interval。

### debounce

每次事件 `Reset` 一个 timer，只有安静窗口结束才执行。回调和 event loop 必须串行化，避免 Reset 与处理竞态。

### `AfterFunc` 清理桥

适合把 context 取消桥接到不接受 context 的阻塞资源；stop 不等待回调，因此需独立完成信号，且 close/cleanup 要幂等。

## 6. NGF：WAF poller 的周期合同

`internal/framework/waf/poller/poller.go:poller.run`：

1. sources 为空立即返回，不创建 ticker；
2. 取所有 source 最小 interval 作为 tick；非正值记录错误并回退默认；
3. 启动时立即轮询所有 source，并记录各自 `lastPoll`；
4. 创建 `time.NewTicker(minInterval)`，立即 `defer ticker.Stop()`；
5. select 在 `ctx.Done()` 与 `ticker.C` 间等待；
6. 每 tick 按 `now.Sub(lastPoll[key]) >= src.Interval` 判断各 source 是否到期；
7. context 取消时日志并返回，defer Stop 执行。

这不是“每 source 一个 ticker”，而是单一最小节拍 + 每 source 上次时间，减少 timer 数。tick 可能被丢，判断用 ticker 给出的 `now` 与 lastPoll 差值，不依赖每个 tick 都到达。

`poller_test.go:Test_poller_runExitsOnContextCancel` 与 no-sources 测试证明两个退出分支；poll source tests 证明 unchanged/changed/fetch error 行为，但不是精确实时性基准。

## 7. 对照：TLS FileWatcher

`filewatcher.Watch` 创建 `ticker := time.NewTicker(w.interval)`，select 监听 ctx、fsnotify Events、ticker.C、Errors。ctx 取消时关闭 watcher 并返回。

在基线 `918d0fa7`，该函数没有显式 `ticker.Stop()`。Go 1.26 中返回后 ticker 不可达时可被 GC 回收，因此不能声称永久泄漏；但在函数返回到 GC 回收之间仍缺少显式停止，且所有权不如 WAF poller 清晰。迁移建议是创建后立即 `defer ticker.Stop()`。

## 8. 失败与误区

- 热循环 `time.After`：每轮创建新 timer；复用 Timer/Ticker；
- Stop 后 range `ticker.C` 等关闭：Stop 不 close；另用 context/done；
- Go 1.26 仍无条件 drain：可能死锁；
- `AfterFunc.Stop` 当 join：false 不表示回调完成；
- ticker 当可靠消息队列：慢消费者会丢 tick；
- 外层 timeout 返回但下游不接 ctx：后台工作继续；
- 每次重试重置完整 timeout：总预算被无限扩张；从 parent deadline 取剩余预算。

## 9. 迁移边界

可直接迁移：WAF poller 的“立即一次 + 周期后续 + ctx 退出 + defer Stop”；Go 1.26 直接 Reset channel timer。

有条件迁移：最小节拍适合 source 数不大、间隔近似倍数且允许 tick 粒度误差；大量 source 应考虑 heap scheduler。

不要照搬：旧版 Stop+drain 模板必须按目标 Go 版本；Ticker 不适合保证每个周期事件都被处理。

## 10. 练习与答案

1. `Ticker.Stop` 会 close C 吗？——不会。
2. Go 1.26 Reset 前需 Stop+drain 吗？——channel timer 不需要。
3. `AfterFunc` Stop=false 表示回调结束吗？——不表示；可能刚开始或已被 stop。
4. WAF poller 为何先 poll 再 ticker？——避免启动后空等一个 interval。
5. FileWatcher 未 Stop 是否可称永久泄漏？——Go 1.26 不可；GC 可回收，但显式 Stop 更及时清晰。

## 源码证据索引

- **版本事实** Go 1.26.0 `go doc -all time` 与 `$GOROOT/src/time/sleep.go,tick.go`
- **源码事实** `ngf:internal/framework/waf/poller/poller.go:poller.run`
- **测试佐证** `ngf:internal/framework/waf/poller/poller_test.go:Test_poller_runExitsOnContextCancel,Test_poller_runExitsWithNoSources`
- **源码事实** `ngf:internal/controller/nginx/agent/grpc/filewatcher/filewatcher.go:Watch`

下一步：[[46-Mutex-RWMutex与临界区]]、[[49-EventLoop批处理与状态所有权]]。
