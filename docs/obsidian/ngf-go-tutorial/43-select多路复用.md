---
title: "43 select 的多路复用语义"
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

# 43 select 的多路复用语义

> [!abstract]
> `select` 在一组 channel 通信中选择：一个 case 就绪就执行；多个同时就绪时做伪随机选择；都不就绪时阻塞，除非有 `default`。源码顺序不是优先级，closed receive 永远就绪，nil channel 永不就绪。

## 学习目标与前置

- 从零掌握 receive/send/default/空 select；
- 准确处理随机就绪、nil、closed 和 comma-ok；
- 避免 default 热循环与“取消 case 优先”幻觉；
- 逐阻塞点追踪 NGF Broadcaster 的取消保证。

前置：[[41-channel方向与所有权]]、[[42-channel缓冲背压]]。

## 1. 基本语法

**说明性示例：**

```go
select {
case v, ok := <-in:
	_ = v
	_ = ok
case out <- value:
case <-ctx.Done():
	return
default:
	// 此刻没有通信可完成
}
```

case 只能是 channel send/receive，可带短变量声明。case 的 channel 操作数和 send 右侧表达式在进入 select 时求值一次。没有 case 的 `select {}` 永久阻塞。

## 2. ready、阻塞与伪随机选择

执行步骤的心智模型：

1. 评估每个 case 的 channel/发送值；
2. 找出无需阻塞即可完成的通信；
3. 若有一个，选它；若有多个，伪随机选一个；
4. 若没有且有 default，执行 default；
5. 若没有且无 default，阻塞直到至少一个可完成。

```go
select {
case <-ctx.Done(): // 写在第一行不代表优先
case job := <-jobs:
	process(job)
}
```

若取消和 job 同时 ready，二者都可能被选。需要“取消后绝不开始新任务”时，收到 job 后再检查 `ctx.Err()`；长期正确性还需要任务幂等或可取消，不能依赖 case 顺序。

## 3. nil 与 closed channel 的对偶

| channel 状态 | receive case | send case |
|---|---|---|
| nil | 永不 ready | 永不 ready |
| open、无配对/无空间 | 未 ready | 未 ready |
| open、有值/有配对/有空间 | ready | ready |
| closed 且排空 | 永远 ready，零值 `ok=false` | 选择后 panic |

closed receive 放在循环 select 中会永久抢占其他 case。正确做法是 comma-ok 检测，然后将局部 channel 变量设 nil，动态禁用该 case。

> [!danger]
> select 不会保护对 closed channel 的发送。send case 若被选中仍 panic；必须用关闭所有权协议消除 send/close 竞态。

## 4. 可独立运行 demo：动态合并两路输入

```go
package main

import "fmt"

func merge(a, b <-chan int) <-chan int {
	out := make(chan int)
	go func() {
		defer close(out)
		for a != nil || b != nil {
			select {
			case v, ok := <-a:
				if !ok {
					a = nil
					continue
				}
				out <- v
			case v, ok := <-b:
				if !ok {
					b = nil
					continue
				}
				out <- v
			}
		}
	}()
	return out
}

func source(values ...int) <-chan int {
	ch := make(chan int, len(values))
	for _, v := range values {
		ch <- v
	}
	close(ch)
	return ch
}

func main() {
	for v := range merge(source(1, 3), source(2, 4)) {
		fmt.Println(v)
	}
}
```

```bash
gofmt -w main.go && go run main.go
# 输出 1,2,3,4 各一次；跨输入顺序不保证
```

删掉两个 `a=nil`/`b=nil`：closed case 将永远 ready，循环持续收到零值，无法正确结束。这是本章的重要失败实验。

## 5. 常用模式

### 模式一：receive-or-cancel

```go
select {
case v := <-in:
	return v, nil
case <-ctx.Done():
	return zero, ctx.Err()
}
```

若 input 可关闭，必须处理 comma-ok。

### 模式二：send-or-cancel

```go
select {
case out <- v:
	return nil
case <-ctx.Done():
	return ctx.Err()
}
```

防止下游消失时发送者泄漏。

### 模式三：timeout

一次性简单等待可用 `time.NewTimer` 并 stop；热循环不要每轮 `time.After`，见 [[45-timeout-timer与ticker生命周期]]。

### 模式四：nil 动态开关

当当前没有待发送数据时令 `out=nil`；有数据时设置真实 channel。这样一个 event loop 可在输入和条件输出间切换，无需 default 轮询。

### 模式五：best-effort

`select { case out <- v: default: }` 明确表示“此刻不能发送就丢/合并”。需要指标或另存状态；详见 [[42-channel缓冲背压]]。

## 6. default busy loop

```go
for {
	select {
	case v := <-in:
		use(v)
	default:
	}
}
```

没有工作时它仍以最高速度循环，占满 CPU。修复通常是删除 default 让 select 阻塞，或用 ticker/条件 channel 驱动。`runtime.Gosched()` 和短 sleep 只是轮询退让，不会建立清晰的唤醒协议。

default 适合真正的 non-blocking API，不适合“我不想思考等待条件”。

## 7. NGF：Broadcaster 每个阻塞点都可取消

`DeploymentBroadcaster.publisher` 给每个 listener 启动 worker，先交付消息：

**NGF 缩写源码：**

```go
select {
case <-channels.listenerCtx.Done():
	return
case <-b.broadcasterCtx.Done():
	return
case channels.listenCh <- msg:
}
```

再等待 ACK：

**NGF 缩写源码：**

```go
select {
case <-channels.listenerCtx.Done():
	return
case <-b.broadcasterCtx.Done():
	return
case <-channels.responseCh:
	return
}
```

调用/失败路径：

1. 正常：send ready → listener 处理 → response ready → worker 返回；
2. 发送前退订：listener Done ready，worker 返回；
3. 收到消息但永不 ACK 后退订：第二个 listener Done 解锁；
4. 全局 shutdown：broadcaster Done 解锁任一阶段；
5. 所有 workers 返回后 `wg.Wait` 完成；publisher 再在 broadcaster Done 与 `doneCh <-` 间 select；
6. `Send` 也分别用 publish-or-cancel 与 done-or-cancel，shutdown 不会卡住调用者。

`subscriber` 的主循环在 broadcaster Done、`subCh`、`unsubCh` 间选择；退订时先 cancel listener 再从 map 删除。`CancelSubscription` 向 `unsubCh` 发送时也带 shutdown 分支。

### 测试证据

`broadcast_test.go` 分开覆盖 shutdown 时 listener 已收到/未收到消息，以及取消 subscription 时已收到/未收到消息。这个拆分很重要：只测试 ACK 等待不能证明发送阻塞也可解除。

> [!note]
> 同时 ready 时取消无优先级，因此 shutdown 边界可能仍完成一次通信。这里安全性来自后续阶段仍有取消分支和操作幂等预期，不来自 select 偏好取消。

## 8. 失败与误区

- 把第一 case 当高优先级；
- closed receive 不设 nil，形成零值热循环；
- 认为 send-to-closed 会被其他 ready case“遮住”；
- default 循环当作低成本监听；
- 只有外层 select 监听取消，内层 send/ACK 永久阻塞；
- `time.After` 在热循环中反复创建 timer；
- 收到工作后不再检查取消，又启动昂贵不可中断调用；
- 多路输入要求严格公平：select 不提供业务级公平/SLA。

## 9. 迁移边界

可直接迁移：每个潜在永久阻塞操作都提供取消 case；closed input 设 nil；non-blocking 行为显式命名和计数。

有条件迁移：Broadcaster 的双层取消适合“单 listener 可取消 + 整体可 shutdown”；简单 worker 只需一层 context。

不要照搬：需要优先级队列时不能依赖 select 源码顺序；应先读取高优先级队列或用显式调度器。需要严格轮询公平时也应另建算法。

## 10. 练习与答案

1. `ctx.Done()` 和 jobs 同时 ready，哪个先？——伪随机选择，未指定。
2. closed channel receive 为什么要设 nil？——否则永久 ready，反复返回零值。
3. nil channel 放 select 有何用？——动态禁用 case，不占用 goroutine。
4. 如何修复 default 热循环？——删除 default 让事件驱动阻塞，或增加明确 timer/通知源。
5. Broadcaster 为何发送和 ACK 分成两个 select？——它们是两个独立阻塞阶段，都必须可被 listener/global cancel 解锁。

## 源码证据索引

- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:publisher,Send,subscriber,CancelSubscription`
- **测试佐证** `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go:TestShutdown_*,TestCancelSubscription_*`
- **版本事实** Go 1.26.0 select/channel language semantics；基线 `918d0fa7`

下一步：[[44-context传递与取消]]、[[45-timeout-timer与ticker生命周期]]、[[49-EventLoop批处理与状态所有权]]。
