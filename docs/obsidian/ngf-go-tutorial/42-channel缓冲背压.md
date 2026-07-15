---
title: "42 缓冲、无缓冲 channel 与背压"
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

# 42 缓冲、无缓冲 channel 与背压

> [!abstract]
> 无缓冲 channel 把一次发送和一次接收直接配对；容量 N 允许最多 N 个未接收值排队。缓冲只吸收有限突发，不会创造消费能力。容量、阻塞、丢弃、合并和批处理必须由业务语义决定。

## 学习目标与前置

- 精确理解 `make(chan T)`、`make(chan T, n)`、`len`、`cap`；
- 建立吞吐、等待时间、积压与内存的直觉；
- 选择阻塞、超时、丢弃、覆盖/合并、批处理策略；
- 比较 NGF status Queue 的单槽通知与 Broadcaster 的无缓冲握手。

前置：[[41-channel方向与所有权]]、[[43-select多路复用]]。

## 1. 从零语法与状态

**说明性示例：**

```go
handoff := make(chan Job)       // cap=0
queue := make(chan Job, 8)      // cap=8
fmt.Println(len(queue), cap(queue))
```

| 类型 | 发送完成条件 | 接收完成条件 | 语义重点 |
|---|---|---|---|
| 无缓冲 | 接收操作已配对 | 发送操作已配对 | 交接与同步 |
| 有缓冲且未满 | 值进入槽位 | 有排队值 | 解耦短时调度 |
| 有缓冲且已满 | 等接收释放槽位 | 立即取队首 | 背压回到发送者 |
| nil | 永不完成 | 永不完成 | `select` 动态禁用 |
| closed 且排空 | 发送 panic | 零值、`ok=false` | 流终止 |

`len(ch)` 是此刻已排队元素数，`cap(ch)` 是固定容量。两者是观察值，不是事务：在“检查 len”和“发送”之间，其他 goroutine 可以改变状态。不要写 `if len(ch) < cap(ch) { ch <- v }` 来实现非阻塞发送；应用 `select/default`。

## 2. 背压的心智模型

生产速率长期高于消费速率时，任何有限队列最终都会满。加大缓冲只会推迟阻塞，并可能增加：

- 排队等待时间和结果陈旧度；
- 每个元素占用的内存；
- shutdown 时需排空的工作量；
- 故障恢复后的突发压力。

Little's law 的工程直觉是：稳定系统中，“平均在途数量”约等于“平均到达率 × 平均停留时间”。它帮助提出问题，但本笔记没有 NGF 的生产测量数据，不能据此虚构容量。选容量前要测到达率分布、处理耗时、允许延迟和单元素成本，并给过载行为。

> [!warning]
> “容量设为 1000 比 100 更安全”没有依据。若消费者永久停止，二者都会满；若元素很大，1000 可能把背压变成 OOM。

## 3. 可独立运行 demo：四种过载策略

```go
package main

import (
	"context"
	"fmt"
	"time"
)

func blocking(ctx context.Context, out chan<- int, v int) error {
	select {
	case out <- v:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func dropNewest(out chan<- int, v int) bool {
	select {
	case out <- v:
		return true
	default:
		return false
	}
}

func notify(out chan<- struct{}) {
	select {
	case out <- struct{}{}:
	default: // 已有唤醒令牌，合并
	}
}

func main() {
	jobs := make(chan int, 1)
	jobs <- 1
	fmt.Println("accepted newest:", dropNewest(jobs, 2))

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	fmt.Println("blocking result:", blocking(ctx, jobs, 3))

	wake := make(chan struct{}, 1)
	notify(wake)
	notify(wake)
	fmt.Println("wake tokens:", len(wake))
}
```

```bash
gofmt -w main.go && go run main.go
# accepted newest: false
# blocking result: context deadline exceeded
# wake tokens: 1
```

失败路径已被执行：满队列上，best-effort 明确丢弃；可靠发送受预算约束后返回 deadline error；两次通知合并为一个 token。

## 4. 五种常用模式

### 模式一：可靠阻塞

任务不可丢时让发送等待，并加入 `ctx.Done()`。压力传播到入口，由入口拒绝、限速或超时。

### 模式二：有界突发缓冲

容量来自“最多允许排队多少工作/内存/延迟”。队列满后的行为仍必须定义，不能停在“有 buffer”。

### 模式三：best-effort 丢弃

```go
select {
case metrics <- sample:
default:
	dropped.Add(1)
}
```

适合允许损失的遥测；必须有 drop 指标。业务命令通常不可静默丢弃。

### 模式四：单槽通知合并

真实状态存于锁保护的结构，`chan struct{}` 只表示“可能有工作”。容量 1 + 非阻塞 send 合并重复唤醒，不丢真实状态。

### 模式五：批处理

消费者被唤醒后一次取多项，摊薄固定成本。要限制批量或时间片，避免新工作长期饥饿。NGF EventLoop 的双缓冲见 [[49-EventLoop批处理与状态所有权]]。

## 5. NGF 真实用法一：status Queue 的通知合并

`internal/controller/status/queue.go:NewQueue` 构造：

**NGF 原样源码节选：**

```go
items:    []*QueueObject{},
notifyCh: make(chan struct{}, 1),
```

`Enqueue` 在 mutex 内先 append 真实数据，再尝试非阻塞通知：

**NGF 原样源码节选：**

```go
q.items = append(q.items, item)
select {
case q.notifyCh <- struct{}{}:
default:
}
```

状态路径：

1. `items` 是数据源，源码注释明确称它为 unlimited size；
2. `notifyCh` 只是唤醒，不与每个 item 一一对应；
3. 第一个 enqueue 放 token，后续 enqueue 可合并通知；
4. `Dequeue` 在空队列时临时解锁，等待 `ctx.Done()` 或 token；
5. 被唤醒后重新加锁并用 `for len(items)==0` 重检条件；
6. 取队首并缩短 slice。

没有 lost wake-up：append 和通知在同一锁区间；消费者每次在锁内检查 `items`。即使 token 数少于 item 数，只要队列非空，后续 `Dequeue` 不等待 token。

### 真实风险边界

单槽 channel 是有界的，但 `items` 不是。若生产长期快于消费，通知合并不会限制内存；迁移到新项目时若需要真正背压，应使用有界数据队列或入口限流，而不是只复制 `notifyCh`。

`queue_test.go` 覆盖 enqueue/dequeue、多 item 和 context 取消；这些测试证明队列协议，不证明生产负载下的容量上界。

## 6. NGF 真实用法二：Broadcaster 选择背压握手

Broadcaster 的 `publishCh`、listener `listenCh`、`responseCh` 都无缓冲。一次 `Send` 的完成条件是 publisher 接收消息、并发交给当前 listeners、每个 listener 响应或被取消，然后发送 `doneCh`。

这是协议背压，不是容量遗漏：配置应用需要等待 ACK。给 `responseCh` 加 buffer 并不能让 agent 更快；若改变 `Send` 完成时机，还可能错误地把“已排队”当成“已应用”。

## 7. 策略选择矩阵

| 数据语义 | 推荐策略 | 满载行为 | 必要观测 |
|---|---|---|---|
| 不可丢命令 | 有界 + 阻塞/拒绝 | 返回错误或上游等待 | depth、wait、reject |
| 最新状态 | 覆盖/合并 | 丢旧状态 | coalesced、age |
| 唤醒信号 | 单槽通知 | 合并 token | queue depth |
| 遥测样本 | best-effort | 丢新/采样 | dropped |
| 请求/ACK | 无缓冲或显式 in-flight | timeout/cancel | latency、timeout |

## 8. 失败与误区

- 用 buffer 修 goroutine 泄漏：只延迟暴露；
- `len(ch)` 后再 send：有检查-使用竞态；
- 默认分支静默丢任务：把容量问题变成数据损坏；
- 认为 `cap == worker 数`：worker 并发和等待容量是不同维度；
- 无限 slice + 单槽通知称为“有界队列”：实际数据仍无界；
- 给握手 channel 加 buffer：可能改变完成语义；
- 关闭 channel 当清空队列：close 不丢已排队值。

## 9. 迁移边界

可直接迁移：单槽通知用于“状态另存、重复唤醒等价”的场景；可靠发送使用 send-or-cancel；丢弃必须计数。

有条件迁移：NGF Queue 需要外部负载保证；新项目若面对用户可控洪峰，应设置真正容量、拒绝策略和指标。

不要照搬：配置 ACK 协议不能换成 best-effort；遥测 drop 模式不能用于状态更新。容量必须来自测量，不从 CPU 数或经验常数猜。

## 10. 练习与答案

1. demo 把 jobs 容量改成 0 时 `dropNewest` 怎样？——无接收者 ready，返回 false。
2. 为什么 notify 两次只有一个 token却不丢工作？——token 不是工作；真实工作在另一个状态容器。
3. status Queue 是否有内存背压？——没有；`items` 无界，channel 只合并通知。
4. 到达 500/s、处理 400/s，扩大有限容量能永久稳定吗？——不能，净积压持续增长；需降速、扩容或拒绝。

## 源码证据索引

- **源码事实** `ngf:internal/controller/status/queue.go:Queue,NewQueue,Enqueue,Dequeue`
- **测试佐证** `ngf:internal/controller/status/queue_test.go`
- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:Send,publisher`
- **测试佐证** `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go`
- **推断边界** 未使用生产流量测量；本文不为 NGF 推导数值容量

下一步：[[43-select多路复用]]、[[45-timeout-timer与ticker生命周期]]、[[49-EventLoop批处理与状态所有权]]。
