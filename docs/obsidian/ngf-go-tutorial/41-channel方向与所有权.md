---
title: "41 channel 方向与所有权表达"
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

# 41 channel 方向与所有权表达

> [!abstract]
> channel 的方向是编译期能力：`chan T` 可收可发，`<-chan T` 只收，`chan<- T` 只发。它不自动决定谁能关闭；关闭权来自协议——只有能证明“以后绝不会再发送”的协调者才能关闭。

## 学习目标与前置

- 从零掌握创建、发送、接收、`close`、comma-ok 与 `range`；
- 读懂三种 channel 类型的赋值和操作矩阵；
- 为单生产者、多生产者、请求/响应定义关闭权；
- 迁移 NGF `SubscriberChannels` 的能力收窄设计。

前置：[[40-goroutine启动与退出责任]]。

## 1. channel 是带同步语义的类型

**说明性示例：**

```go
ch := make(chan int)     // 双向、无缓冲
ch <- 42                 // 发送
v := <-ch                // 接收
v, ok := <-ch            // ok=false 表示已关闭且已排空
close(ch)                // 宣告未来不再发送
```

`make` 返回可用 channel；未初始化的 channel 零值是 `nil`。channel 保存的是 `T` 值，并在 goroutine 间建立同步关系，不是普通 slice 队列。

### 三种类型

**说明性示例：**

```go
var both chan int
var recv <-chan int
var send chan<- int

both = make(chan int)
recv = both // 双向能力收窄为只收
send = both // 双向能力收窄为只发
```

方向写在箭头所指的一侧：`<-chan T` 的值从 channel 流出；`chan<- T` 的值流入 channel。

### 赋值与操作矩阵

| 静态类型 | 可赋给 `chan T` | 可赋给 `<-chan T` | 可赋给 `chan<- T` | 收 | 发 | close |
|---|---:|---:|---:|---:|---:|---:|
| `chan T` | 是 | 是 | 是 | 是 | 是 | 是 |
| `<-chan T` | 否 | 是 | 否 | 是 | 否 | 否 |
| `chan<- T` | 否 | 否 | 是 | 否 | 是 | 是 |

只发 channel 在语法上仍可 `close`；这只是“具备发送侧操作能力”，并不证明调用者在业务协议上拥有关闭权。方向一旦收窄，不能用普通赋值恢复双向能力。

## 2. 关闭与排空的状态机

关闭不是发送一个特殊值。`close(ch)` 改变 channel 状态：

1. 关闭前已排队的值仍按顺序被接收；
2. 排空后接收立即得到 `T` 的零值及 `ok=false`；
3. 向 closed channel 发送会 panic；
4. 再次关闭会 panic；
5. 关闭 nil channel 会 panic；
6. 从 nil channel 接收、向 nil channel 发送都永久阻塞。

```go
v := <-ch            // 只有值，无法区分真实零值和关闭
v, ok := <-ch        // 协议需要识别关闭时使用
for v := range ch {  // 等价于不断接收，直至关闭且排空
	_ = v
}
```

> [!warning]
> `range` 的退出条件是 channel 关闭，不是“暂时没有值”。如果协议永不 close，`range` 就需要另一个取消机制，不能自行结束。

## 3. 可独立运行 demo：多生产者与唯一关闭者

下面是完整可运行程序。两个 producer 只获得发送能力；coordinator 等所有 producer 返回后关闭；consumer 用 `range` 排空。

```go
package main

import (
	"fmt"
	"sync"
)

func produce(id int, out chan<- string, done *sync.WaitGroup) {
	defer done.Done()
	for n := 1; n <= 2; n++ {
		out <- fmt.Sprintf("p%d:%d", id, n)
	}
}

func coordinateClose(out chan<- string, done *sync.WaitGroup) {
	done.Wait()
	close(out)
}

func consume(in <-chan string) int {
	count := 0
	for value := range in {
		fmt.Println(value)
		count++
	}
	return count
}

func main() {
	values := make(chan string)
	var producers sync.WaitGroup
	producers.Add(2)
	go produce(1, values, &producers)
	go produce(2, values, &producers)
	go coordinateClose(values, &producers)
	fmt.Println("count:", consume(values))
}
```

```bash
gofmt -w main.go && go run main.go
# p1/p2 的相对次序不固定；最后一行固定为 count: 4
```

失败实验：让任一 producer 执行 `close(out)`，另一个 producer 可能随后发送并 panic。问题不是“close 不安全”，而是它不能证明其他发送者已结束。

## 4. 常用模式

### 模式一：函数参数收窄

```go
func Produce(out chan<- Item)
func Consume(in <-chan Item)
```

签名记录最小权限，调用点仍可传入双向 channel。

### 模式二：producer 返回只收 channel

```go
func Numbers() <-chan int {
	out := make(chan int)
	go func() {
		defer close(out)
		out <- 1
		out <- 2
	}()
	return out
}
```

创建者也是唯一发送者，因此能安全 close；调用者不能误发。

### 模式三：关闭 done channel 做广播

多个接收者都能观察 `<-done`；一次 `close(done)` 同时唤醒它们。必须保证唯一关闭者，或用 `sync.Once` 包装。

### 模式四：请求/响应双通道

数据向消费者流动，ACK 反向流动。两条 channel 各自收窄，比暴露两个双向 channel 更能表达协议。

### 模式五：多生产者 coordinator

producers 只发；`WaitGroup` 证明所有发送完成；coordinator 独占 close；consumer range。这是 fan-in 的标准关闭骨架，详见 [[47-WaitGroup与fan-out-fan-in]]。

## 5. NGF 真实用法：同一通道的两种能力视图

`internal/controller/nginx/agent/broadcast/broadcast.go` 对订阅者公开：

**NGF 原样源码节选：**

```go
type SubscriberChannels struct {
	ListenCh   <-chan NginxAgentMessage
	ResponseCh chan<- struct{}
	ID         string
}
```

订阅者只能收配置消息、发 ACK。Broadcaster 内部保存反向视图：

**NGF 缩写源码：**

```go
type storedChannels struct {
	listenCh   chan<- NginxAgentMessage
	responseCh <-chan struct{}
	// listenerCtx、cancel、id 省略
}
```

调用与状态路径：

1. `Subscribe` 创建两个双向无缓冲 channel；
2. 同一底层 channel 被包装成两种不同静态能力；
3. `publisher` 向 `listenCh` 发消息；
4. agent subscription 从 `ListenCh` 收到并处理；
5. subscription 向 `ResponseCh` 发 ACK；
6. publisher 从 `responseCh` 收到后完成该 listener worker。

这里没有关闭两个数据 channel。取消订阅会调用 listener `CancelFunc`；进程 shutdown 会取消 broadcaster context。这样能同时解除“尚未发出消息”和“等待 ACK”两个阻塞点，避免 send/close 竞态。

### 失败路径与测试证据

- `Subscribe` 遇到 broadcaster 已取消，会返回能力收窄后的 channel，但不登记 listener；
- `CancelSubscription` 删除 listener 前调用其 cancel，正在发送或等 ACK 的 worker 都能退出；
- 父 context 取消级联终止全部 listener；
- `broadcast_test.go` 的 subscribe、多 listener、cancel 和 shutdown 场景证明握手与解阻塞行为。

> [!note]
> 方向类型只证明“这段代码不能执行某种操作”，不证明对端存在、一定消费、一定 ACK，亦不提供超时或公平性。

## 6. 失败与误区

- 接收者因“不再需要”而 close：可能撞上发送者；应发取消信号；
- 为释放内存而 close：channel 会随不可达对象被回收，close 是协议事件；
- 用零值判断结束：合法零值会被误判，应用 comma-ok；
- 多发送者各自 defer close：关闭权分裂；
- 把 `<-chan T` 强转回双向：普通类型转换不允许恢复能力；
- 忘记 nil：赋值前启动 goroutine 可能永久阻塞。

## 7. 迁移边界

可直接迁移：公开 API 使用最窄方向、单 producer 创建并 close、coordinator 等待所有发送者后 close。

有条件迁移：done-close 广播要求唯一关闭者；请求/ACK 要为取消、超时和重复响应定义语义。

不要照搬：若状态本来由同一对象并发读写，锁可能比“每个字段一个 channel”更清楚；若只返回一个值，普通 `(T, error)` 更简单。

## 8. 练习与答案

1. `chan<- T` 为什么语法上可 close？——close 属于发送侧终止协议，但业务上仍需拥有关闭权。
2. buffered channel close 后还有两个值，range 得到几个？——先得到两个，再结束。
3. 两个 producer 怎样保证安全关闭？——各自返回，coordinator `Wait` 后唯一 close。
4. Broadcaster 为什么不 close `listenCh`？——订阅取消与全局 shutdown 由 context 表达，可解开所有阻塞阶段并避免并发发送撞 close。

## 源码证据索引

- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:SubscriberChannels,storedChannels`
- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:Subscribe,publisher,CancelSubscription`
- **测试佐证** `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go`
- **版本事实** Go 1.26.0 language/channel semantics；仓库基线 `918d0fa7`

下一步：[[42-channel缓冲背压]]、[[43-select多路复用]]、[[47-WaitGroup与fan-out-fan-in]]。
