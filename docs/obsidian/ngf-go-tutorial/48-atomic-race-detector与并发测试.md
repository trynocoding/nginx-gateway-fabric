---
title: "48 atomic、race detector 与并发测试"
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

# 48 atomic、race detector 与并发测试

> [!abstract]
> atomic 适合一个可独立解释的标量状态；操作不可分割且在 Go 中提供顺序一致语义。它不把多步协议自动变成原子事务。race detector 发现“未同步的并发内存访问”，不证明无死锁、无丢更新、无泄漏或业务顺序正确。

## 学习目标与前置

- 从零掌握 typed atomic 的 Load/Store/Swap/CAS/Add；
- 理解 sequential consistency 与 synchronizes-before 的可见性；
- 区分 data race、logical race 与死锁；
- 用 `go test -race` 和确定性同步测试 NGF 风格并发代码。

前置：[[46-Mutex-RWMutex与临界区]]、[[47-WaitGroup与fan-out-fan-in]]。

## 1. 为什么 `x++` 不是原子操作

普通 `x++` 包含读取、加一、写回。两个 goroutine 可都读旧值，各写同一新值，造成丢更新；如果未同步，这还是 data race。

Go 1.26 推荐 typed atomic：

**说明性示例：**

```go
var count atomic.Int64
count.Add(1)
fmt.Println(count.Load())

var changed atomic.Bool
changed.Store(true)
old := changed.Swap(false)
```

还有 `atomic.Uint32/Uint64/Uintptr/Pointer[T]` 等。零值可用；首次使用后不得复制。把它放进 struct 时用指针接收者，避免复制内部 `noCopy`/状态。

## 2. 操作语义

| 操作 | 含义 | 常见用途 |
|---|---|---|
| `Load` | 原子读取 | 快照 flag/counter |
| `Store` | 原子写 | 发布 flag |
| `Swap` | 写新值并返回旧值 | 取走 pending 标记 |
| `CompareAndSwap(old,new)` | 值仍为 old 才更新 | 一次状态跃迁/抢所有权 |
| `Add(delta)` | 原子加并返回新值 | 计数器、序号 |

Go atomic 操作表现为顺序一致：若 atomic A 的效果被 atomic B 观察到，则 A synchronizes-before B；所有 atomic 操作可解释为某个全局顺序。这比许多语言默认原子序更强，但仍只覆盖参与协议的内存关系。

```go
payload = "ready"   // 普通写
ready.Store(true)   // 发布

if ready.Load() {   // 观察发布
	fmt.Println(payload)
}
```

前提是 payload 只按这个发布协议访问；如果其他路径无同步写 payload，仍有 race。

## 3. atomic 不等于事务

```go
if changed.Load() {
	notify()
	changed.Store(false)
}
```

每一步原子，但整体不是：另一个 goroutine 可在 Load 后 Store(true)，最后的 Store(false) 覆盖新事件。若确实允许并发生产，`if changed.Swap(false) { notify() }` 能原子“取走”旧标记，但 notify 失败时是否恢复 true 又是业务协议。

两个字段要求一致快照时，分别 atomic 通常不够。可用 Mutex 保护复合不变量，或构造不可变 snapshot 后用 `atomic.Pointer[T]` 一次发布整个版本。

## 4. 可独立运行 demo：CAS 抢一次初始化

```go
package main

import (
	"fmt"
	"sync"
	"sync/atomic"
)

func main() {
	var owner atomic.Int64
	var wins atomic.Int64
	var wg sync.WaitGroup
	for id := int64(1); id <= 8; id++ {
		wg.Go(func() {
			if owner.CompareAndSwap(0, id) {
				wins.Add(1)
			}
		})
	}
	wg.Wait()
	fmt.Println("owner nonzero:", owner.Load() != 0)
	fmt.Println("wins:", wins.Load())
}
```

```bash
gofmt -w main.go && go run -race main.go
# owner nonzero: true
# wins: 1
```

owner 值不确定，但 CAS 保证只有一个 0→id 成功；race detector 不报告 data race。

## 5. 常用模式

### 单调计数器

请求数、drop 数、序号用 `atomic.Uint64.Add`。如果计数与其他状态必须一起重置，改用锁。

### sticky/pending flag

生产者 Store(true)，消费者 Swap(false)。业务要允许多个事件合并成一次处理；否则 bool 会丢事件计数。

### immutable snapshot 发布

构造完整只读对象后 `atomic.Pointer[Config].Store(ptr)`，reader Load 后只读。禁止发布后修改对象；更新用 copy-on-write。

### 一次状态转换

CAS 把 `starting→running`；状态多且转换复杂时 Mutex/state machine 更易审计。

### 指标与 fast path

atomic 适合高频独立标量。不要为了“无锁”把复杂协议拆成多个难以证明的原子字段。

## 6. race detector 能证明什么

运行：

```bash
go test -race ./path/to/package
go test -race -count=10 ./path/to/package
```

编译器插桩内存访问；测试执行到两个未建立同步关系且至少一个为写的冲突访问时报告栈。它是动态检测：未执行路径没有证据，某次未报告不等于无 race。

它不会自动发现：

- atomic 多步协议的 lost update；
- channel deadlock；
- goroutine 泄漏；
- select 公平性/错误顺序；
- 锁保护了错误的不变量；
- timeout 过长、队列无界等性能问题。

atomic 会消除相应 data race 报告，但可能“把告警静音却保留逻辑 bug”。先写状态机，再选同步原语。

## 7. 并发测试方法

### 用 channel 制造相位，不用 sleep 猜时序

测试 worker 发 `started` 后阻塞在 `release`；主测试确认它进入临界阶段，再触发取消/第二事件。NGF EventLoop batching 测试正使用这种方法。

### 测试两侧阻塞阶段

消息协议要覆盖“尚未接收”和“已接收但未 ACK”；Broadcaster 测试分别覆盖这两条取消路径。

### 重复、race、超时三层

- 单元断言状态/结果；
- `-race` 检查执行到的访问；
- 测试 context/Eventually 上界防 CI 永久挂起。

### 不并发调用断言库

worker 将结果写 channel，主测试 goroutine 断言；某些测试对象/断言 API 不保证多 goroutine 安全。

## 8. NGF：FileWatcher 的 atomic.Bool

`FileWatcher` 持有 `filesChanged *atomic.Bool`：

**NGF 缩写源码：**

```go
func (w *FileWatcher) handleEvent(event fsnotify.Event) {
	// 过滤 empty/chmod/create；remove/rename 时重新 add watcher
	w.filesChanged.Store(true)
}

func (w *FileWatcher) checkForUpdates() {
	if w.filesChanged.Load() {
		w.notifyCh <- struct{}{}
		w.filesChanged.Store(false)
	}
}
```

生产路径 `Watch` 的 select 在同一 goroutine 串行调用 `handleEvent` 与 `checkForUpdates`；因此该路径本身没有二者并发执行。但 `TestFileWatcher_Watch` 从测试 goroutine轮询 `w.filesChanged.Load()`，同时 Watch goroutine Store；atomic 使这一观测无 data race。

状态含义是“自上次检查后至少发生一个相关事件”，多个 fsnotify event 可合并。测试 `TestFileWatcher_handleEvent` 验证 empty/chmod/create 不置位，write/remove/rename 置位；Watch 测试验证写文件最终置位并发通知。

### 迁移时的并发边界

在当前单 owner Watch loop 中 Load→notify→Store 的多步不是并发问题。若未来允许别的 goroutine 直接调用 `handleEvent`，Load 后 Store(false) 可能覆盖期间的新 Store(true)。这是一项基于代码结构的条件风险，不是当前生产路径已证实 bug；届时应改为 Swap 协议并重新定义通知失败语义，或恢复单 goroutine 所有权。

## 9. 对照：何时用 Mutex

`AgentConnectionsTracker` 的 map、Broadcaster listeners、WAF poller 的 bundle state 都是复合状态，使用 Mutex/RWMutex。把 map 指针塞进 atomic 不会让 map 内修改安全；应发布不可变完整副本或继续锁。

## 10. 失败与误区

- 普通 bool 并发读写；
- 复制 typed atomic；
- 多个 atomic 字段假装一致快照；
- Load 后 Store 当原子消费；
- `-race` 一次通过就宣布并发正确；
- 用 sleep 增加“触发概率”，导致 flaky test；
- atomic pointer 指向的对象发布后仍修改；
- 为性能换 atomic 却没有 benchmark/争用证据。

## 11. 迁移边界与练习答案

可直接迁移：独立 counter/flag、CAS 单次跃迁、`go test -race` 加确定性同步。

有条件迁移：FileWatcher flag 依赖事件可合并与单 goroutine消费；多消费者/逐事件语义不能复制。

不要照搬：复合配置、map、slice in-place mutation 用多个 atomic 字段。

练习：

1. atomic.Bool 能否记录 5 次事件？——只能记录“至少一次”，次数会合并。
2. race-free 是否等于无丢更新？——否，多步原子协议仍可逻辑竞态。
3. Swap(false) 比 Load+Store 多保证什么？——读取旧值与清零是一次不可分割操作。
4. race detector 为何可能漏报？——动态工具只检查本次运行执行到的交错。

## 源码证据索引

- **版本事实** Go 1.26.0 `go doc -all sync/atomic` 与 Go memory model
- **源码事实** `ngf:internal/controller/nginx/agent/grpc/filewatcher/filewatcher.go:FileWatcher,Watch,handleEvent,checkForUpdates`
- **测试佐证** `ngf:internal/controller/nginx/agent/grpc/filewatcher/filewatcher_test.go`
- **源码对照** `ngf:internal/controller/nginx/agent/grpc/connections.go:AgentConnectionsTracker`

下一步：[[49-EventLoop批处理与状态所有权]]。
