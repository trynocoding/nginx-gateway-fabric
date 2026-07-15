---
title: "46 Mutex、RWMutex 与临界区"
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

# 46 Mutex、RWMutex 与临界区

> [!abstract]
> Mutex 不“保护变量名”，而是保护一组共享状态的不变量。所有访问路径必须遵守同一锁协议。RWMutex 只在读多、临界区足够长且测量证明有益时使用；两者首次使用后都不可复制。

## 学习目标与前置

- 从零掌握 `Lock/Unlock`、`RLock/RUnlock` 与 happens-before；
- 识别锁复制、长临界区、锁顺序、重入和升级死锁；
- 使用快照把 channel/I/O/回调移出锁；
- 追踪 NGF Broadcaster listeners 与 connection tracker 的锁边界。

前置：[[12-切片共享与防御性复制]]、[[40-goroutine启动与退出责任]]。

## 1. 从零语法

**说明性示例：**

```go
type Counter struct {
	mu sync.Mutex
	n  int
}

func (c *Counter) Inc() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.n++
}
```

Mutex 零值可用。同一个 goroutine 也不能重复 Lock：Go mutex 不可重入。Unlock 未锁 mutex 会运行时 fatal。一个 goroutine 可以 Lock、另一个 Unlock，但通常表明所有权难懂。

Go 内存模型保证第 n 次 `Unlock` synchronizes-before 后续第 m 次 `Lock`（n < m）；后者能观察前者临界区写入。锁同时提供互斥与可见性。

## 2. RWMutex

```go
func (c *Cache) Get(key string) (Value, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	v, ok := c.values[key]
	return v, ok
}
```

多个 reader 可并发；writer `Lock` 排斥所有 reader/writer。当 writer 等待时，新 reader 会受阻，避免 writer 永久饥饿。因此不能递归 RLock，也不能假设读锁永远立即成功。

RWMutex 不能从 RLock 原地升级为 Lock，也不能从 Lock 降级为 RLock；尝试升级会让自己持有的读锁阻止写锁。应释放后重取，并重新验证条件。

## 3. 不可复制规则

`Mutex`、`RWMutex` 首次使用后不能复制。值接收者会复制包含锁的 struct：

**反例（不可运行生产模式）：**

```go
type Bad struct {
	mu sync.Mutex
	m  map[string]int
}

func (b Bad) Put(k string, v int) { // 错：复制 mutex
	b.mu.Lock()
	defer b.mu.Unlock()
	b.m[k] = v
}
```

不同副本锁住不同 mutex，却共享 map 指针，互斥失效。使用指针接收者，构造后也不要按值复制对象；`go vet -copylocks` 能发现部分错误。

## 4. 可独立运行 demo：快照后慢处理

```go
package main

import (
	"fmt"
	"sync"
)

type Registry struct {
	mu      sync.RWMutex
	workers map[string]func(string)
}

func (r *Registry) Add(name string, fn func(string)) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.workers[name] = fn
}

func (r *Registry) Broadcast(message string) {
	r.mu.RLock()
	snapshot := make([]func(string), 0, len(r.workers))
	for _, fn := range r.workers {
		snapshot = append(snapshot, fn)
	}
	r.mu.RUnlock()

	for _, fn := range snapshot { // 未持锁调用未知代码
		fn(message)
	}
}

func main() {
	r := &Registry{workers: make(map[string]func(string))}
	r.Add("printer", func(s string) { fmt.Println(s) })
	r.Broadcast("ready")
}
```

```bash
gofmt -w main.go && go run main.go
# ready
```

若把 callbacks 留在 RLock 内调用，callback 一旦回调 `Add` 就会等待 Lock，而 Broadcast 又等 callback 返回，形成死锁。快照把未知阻塞移出临界区。

## 5. 临界区设计

先写锁保护的不变量，而非只在字段旁写“mu protects map”：

- map 的键集合与索引必须一致；
- enabled 与 pending 队列切换原子发生；
- 读取多个字段必须来自同一版本；
- slice 返回给调用者前要复制，避免锁外别名修改。

常用模式：

### 原子检查并更新

check 与 mutation 放同一 Lock；不能 RLock 查不存在、解锁、再 Lock 插入而不重检。

### 快照再执行

锁内复制 map/slice/指针列表，锁外做 channel、I/O、日志重活或第三方 callback。要明确快照元素本身是否仍可变；浅拷贝不自动深拷贝。

### defer 与显式 Unlock

短函数用 defer 防早退漏解锁。需要把慢操作移出锁时显式 Unlock 更清楚，但每个 return/panic 路径要审计。

### 分片锁

高争用 map 可按 key 分片；代价是跨分片不变量、全量快照和锁顺序更复杂。先测争用再引入。

### TryLock/TryRLock

只适合极少数避免锁顺序的场景；失败的 TryLock 不建立 synchronizes-before，忙轮询会浪费 CPU。正常代码优先阻塞锁或重构所有权。

## 6. 死锁清单

- 同一 goroutine 二次 Lock；
- 持 RLock 再 Lock 升级；
- 路径 A 按 mu1→mu2，路径 B 按 mu2→mu1；
- 持锁发送无缓冲 channel，而接收方需同一锁；
- 持锁等待 WaitGroup，而 worker 完成前需锁；
- 持锁调用用户回调/I/O；
- 忘记 Unlock 或 panic 跨越手写解锁路径。

锁顺序应写成全局规则；必要时减少同时持有两把锁，而不是靠 sleep 规避。

## 7. NGF：DeploymentBroadcaster 快照边界

`DeploymentBroadcaster.mu sync.RWMutex` 保护 `listeners map[string]storedChannels`。subscriber 在登记/取消时 Lock；`Send` 只为读取 listener 数量 RLock。

publisher 的关键实现：

1. RLock；
2. 新建 map 并复制当前 listener entries；
3. RUnlock；
4. 对 snapshot 中每个 listener `wg.Go`；
5. worker 可能阻塞发送、等待 ACK 或取消；
6. `wg.Wait`；
7. 向 doneCh 发完成信号。

若持 RLock 等 ACK，`CancelSubscription` 的 subscriber 需要 Lock 才能取得 listener 并 cancel，二者会死锁。快照让取消路径能修改 live map 与触发 listener context；snapshot 仍持有 cancelable context/channel，因此 worker 可退出。

这里的语义是“发布开始时的 listener 集合”：快照后新订阅者不收当前消息；快照后取消者可能仍在 snapshot，但它的 listenerCtx 被 cancel，worker退出。这是可验证的边界，不是强一致广播。

`broadcast_test.go` 的多 listener、取消已收/未收消息测试佐证该机制。

## 8. NGF 对照：AgentConnectionsTracker

`AgentConnectionsTracker` 用 RWMutex 保护 `connections map[string]Connection`：Track/Set/Remove 用 Lock，Get 用 RLock。方法是指针接收者，避免复制锁。`GetConnection` 返回 `Connection` 值；其字段为 string 与 NamespacedName 值，因此调用者不会拿到 map 内条目的可变指针。

这比为每次读写经过 event loop 简单，因为操作短、状态按 key 查找且需要并发访问。若 `Connection` 将来加入 map/slice/pointer 字段，返回值复制可能变成浅拷贝，需重新审计别名边界。

## 9. Mutex 还是单 goroutine 所有权

| 需求 | 更合适 |
|---|---|
| 短随机读写、同步返回 | Mutex/RWMutex |
| 强顺序事件、批处理、状态机 | 单 event loop |
| 跨 goroutine 工作交接 | channel |
| 单标量独立状态 | atomic，见 [[48-atomic-race-detector与并发测试]] |

不要把锁和 channel 当互斥选择；Broadcaster 同时用锁保护 registry、channel 传协议消息、context 管取消。

## 10. 失败与迁移边界

常见误区：读 map 不加锁、复制含锁对象、把 RWMutex 当必然优化、锁内日志/I/O、返回内部 slice、用 TryLock 掩盖锁顺序。

可直接迁移：指针接收者、锁内快照锁外慢操作、为不变量选一把锁、测试取消与并发修改。

有条件迁移：RWMutex 需读多且争用测量；小临界区 Mutex 可能更快更清楚。

不要照搬：Broadcaster snapshot 语义只适合“发布开始时集合”；若要求订阅变更与发布线性化，需要更强协议。

## 11. 练习与答案

1. 为什么值接收者危险？——复制锁但可能共享其保护的引用状态。
2. RLock 能升级吗？——不能；释放、Lock、重检。
3. publisher 为何复制 map？——让发送/ACK 等待不占锁，取消能取得写锁。
4. RWMutex 是否总优于 Mutex？——否，读临界区短或争用低时管理成本可能更高。
5. Stop/shutdown 能解开持锁 WaitGroup 吗？——若 worker 需同一锁则不能；Wait 必须锁外。

## 源码证据索引

- **版本事实** Go 1.26.0 `go doc -all sync`
- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster,subscriber,publisher,Send`
- **测试佐证** `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go`
- **源码事实** `ngf:internal/controller/nginx/agent/grpc/connections.go:AgentConnectionsTracker`

下一步：[[47-WaitGroup与fan-out-fan-in]]、[[48-atomic-race-detector与并发测试]]、[[49-EventLoop批处理与状态所有权]]。
