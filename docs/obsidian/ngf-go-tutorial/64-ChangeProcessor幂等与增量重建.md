---
title: "64 ChangeProcessor 幂等与增量重建"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: runtime-flow-tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 64 ChangeProcessor 幂等与增量重建

> [!abstract]
> NGF 的 ChangeProcessor 不是“每来一个事件就局部修补 Graph”。它先把事件幂等地折叠进 `ClusterState`，用 dirty bit 记录是否值得重建，再按批次从当前快照整体执行 `BuildGraph`。这是“增量收集、全量派生”的混合模式。

## 学习目标与前置

- 掌握幂等 Upsert/Delete、dirty bit 和批处理；
- 区分“对象存储发生变化”和“变化与当前 Graph 相关”；
- 理解 `Process` 返回 nil、`ForceRebuild` 和 first event batch；
- 识别锁、指针所有权和失败传播边界；
- 能把这一模式迁移到编译器、配置控制面或物化视图。

前置：[[46-Mutex-RWMutex与临界区]]、[[49-EventLoop批处理与状态所有权]]、[[63-Kubernetes对象到Graph领域建模]]。

## 1. 先理解四个基础操作

```go
type ChangeProcessor interface {
	CaptureUpsertChange(any)
	CaptureDeleteChange(any)
	Process(context.Context) *Graph
	ForceRebuild()
}
```

NGF 的实际接口还提供 `GetLatestGraph()`，并为捕获方法传递具体事件对象。四个核心语义是：

- **Upsert**：key 不存在就插入，存在就替换；重复执行收敛到相同状态；
- **Delete**：存在就删除，不存在通常是 no-op；
- **Process**：dirty 时由完整 `ClusterState` 重建，成功后发布 latest Graph；
- **ForceRebuild**：原始对象不变，但外部输入变化，仍需重新派生。

幂等不是“绝不重复工作”。它是同一最终事件执行一次或多次，最终状态相同。是否避免重复重建，是 dirty/predicate 的另一层优化。

## 2. 为什么选择 dirty bit

最小状态机只有两态：

```text
clean --relevant event/force--> dirty --Process--> clean
  ^                               |
  +--------- Process=nil ---------+
```

多个事件在一次 `Process` 前到达，只需保持 `dirty=true`。这会把 `Gateway Update + Service Update + Secret Delete` 合成一次建图，避免中间 Graph 和中间配置抖动。

> [!note]
> dirty bit 不记录“改了哪些字段”。它牺牲细粒度局部重算，换取状态简单、派生确定和较低的正确性风险。

## 3. 完整可运行 Demo

该程序实现一个缩小版 ChangeProcessor。`BuildGraph` 用当前 Store 计算一份摘要，体现整体替换而不是原地修改旧 Graph。

```go
package main

import (
	"fmt"
	"sort"
	"sync"
)

type Object struct {
	Key     string
	Enabled bool
}

type Graph struct {
	EnabledKeys []string
	Revision    int
}

type Processor struct {
	mu      sync.Mutex
	store   map[string]Object
	dirty   bool
	latest  *Graph
	builds  int
}

func NewProcessor() *Processor {
	return &Processor{store: make(map[string]Object)}
}

func (p *Processor) Upsert(obj Object) {
	p.mu.Lock()
	defer p.mu.Unlock()
	old, exists := p.store[obj.Key]
	p.store[obj.Key] = obj
	if !exists || old != obj {
		p.dirty = true
	}
}

func (p *Processor) Delete(key string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, exists := p.store[key]; !exists {
		return
	}
	delete(p.store, key)
	p.dirty = true
}

func (p *Processor) ForceRebuild() {
	p.mu.Lock()
	p.dirty = true
	p.mu.Unlock()
}

func (p *Processor) Process() *Graph {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.dirty {
		return nil
	}
	p.dirty = false
	p.builds++
	keys := make([]string, 0, len(p.store))
	for key, obj := range p.store {
		if obj.Enabled {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	p.latest = &Graph{EnabledKeys: keys, Revision: p.builds}
	return p.latest
}

func main() {
	p := NewProcessor()
	p.Upsert(Object{Key: "a", Enabled: true})
	p.Upsert(Object{Key: "b", Enabled: false})
	fmt.Printf("first:  %+v\n", p.Process())
	fmt.Printf("clean:  %v\n", p.Process())
	p.Delete("missing")
	fmt.Printf("absent: %v\n", p.Process())
	p.ForceRebuild()
	fmt.Printf("forced: %+v\n", p.Process())
}
```

运行：

```bash
go run main.go
```

预期：第一次合并两个 Upsert 后只构建一次；clean 和删除不存在对象都返回 nil；force 产生 revision 2。

### Demo 与 NGF 的差异

Demo 用 `old != obj` 做语义去重，只适合字段可比较的 struct。NGF 的 `changeTrackingUpdater` 会先按 GVK 配置更新 store，再调用 relevance predicate；nil predicate 表示该类事件总是 dirty。不要据 Demo 推断 NGF 会对所有对象做深比较。

## 4. NGF 的两层结构

### 4.1 changeTrackingUpdater

源码：`internal/controller/state/store.go:changeTrackingUpdater`。

它持有：

- 支持的 GVK 集合；
- `ClusterState` store；
- 每种对象的 predicate；
- 一个 `changed bool`。

Upsert 的顺序是“需要持久化则先写 store，再判断相关性”；Delete 只有在 store 中确实存在时才删除。最终通过：

```go
changed = changed || changing
```

让脏状态具有粘性。`getAndResetChangedStatus` 原子地读取并清零，`forceRebuild` 只设 dirty，不改对象。

传入不支持的 GVK 会 panic。这是程序员/注册不变量失败，不是可恢复的用户配置错误。

### 4.2 ChangeProcessorImpl

源码：`internal/controller/state/change_processor.go:changeProcessorImpl`。

构造器为 GatewayClass、Gateway、HTTPRoute、Service、Secret、EndpointSlice、Policy、Filter 等初始化 map，并把 store 配置与 predicate 交给 updater。捕获与处理都在 processor mutex 下进行。

`Process` 的关键路径是：

1. 获取锁；
2. `getAndResetClusterStateChanged()`；clean 则返回 nil；
3. 合并已有 Graph 与轮询器返回的 WAF bundle，轮询结果覆盖旧值；
4. 调用 `graph.BuildGraph`；
5. 替换 `latestGraph` 并返回它。

因此返回 nil 的含义是“无需重建”，不是“重建失败”，也不是“当前没有 Gateway”。空 Graph 与 nil Graph 必须分开。

## 5. Predicate 是依赖图的反向边

不是所有对象变化都影响当前配置：

- GatewayClass、Gateway、Route 等核心对象使用 nil predicate，即捕获就 dirty；
- Namespace、Service、Secret、ConfigMap、NginxProxy 等用 `isReferenced`；
- EndpointSlice 通过被引用 Service 判断相关性；
- Policy 使用 `isNGFPolicyRelevant`；
- SnippetsFilter、AuthenticationFilter 等需要持续写 status，采用更宽的捕获。

`isReferenced` 读取 latest Graph 的引用集合，实质是“从依赖目标反查哪些输入影响当前图”。这也解释了 [[63-Kubernetes对象到Graph领域建模]] 中为什么要记录尚不存在的 referenced Secret。

> [!warning]
> 过滤过窄会漏掉从“不存在”到“存在”、从“不相关”到“相关”的转变。predicate 必须覆盖依赖关系的边沿，而不只是当前成功解析的对象。

## 6. ForceRebuild 的真实用例

`internal/controller/handler.go:parseAndCaptureEvent` 对 `WAFBundleReconcileEvent` 不调用普通 Upsert，而是先确认对应 poller 活跃，再 `ForceRebuild()`。

原因是该事件携带的是“外部 bundle 已变化”的信号，不是要覆盖 `ClusterState` 中真实 Policy 的完整 Kubernetes 对象。强行 Upsert 一个元数据占位对象，会污染权威观察快照。

迁移判断：当派生结果还依赖文件、证书轮询、远端发现或时钟窗口，而这些输入不属于主 store 时，可使用 force/invalidation 信号；但应记录原因并避免无限重建。

## 7. 第一批事件为什么特殊

`internal/framework/events/first_eventbatch_preparer.go:firstEventBatchPreparer` 在正式接收增量事件前 List/Get 所有相关对象，把现存对象转换为一批 UpsertEvent。命名对象 NotFound 可跳过，其他读取错误会让 EventLoop 启动失败。

第一批提供完整视图，避免启动时按任意 watch 顺序短暂产生大量“引用不存在”状态。对象的批内顺序不重要，因为 ChangeProcessor 先全部 Capture，再 Process 一次。

这也是批处理的强项：建图看到的是“批次收敛后的 store”，而不是事件逐条造成的中间态。

## 8. 锁与错误边界

- 捕获、dirty reset、BuildGraph、latestGraph 替换共享同一处理锁，保证单写；
- `GetLatestGraph` 也加锁，但返回内部指针，调用者仍须遵守只读约定；
- `Process` 无 `error` 返回值，用户资源不合法通常编码进 Graph 条件；
- first batch 的 API 读取错误属于启动基础设施错误，可以显式返回；
- 未支持 GVK/未知事件类型 panic，表示代码注册错误。

注意：`Process` 先清 dirty 再建图。如果未来让 `BuildGraph` 返回可恢复 error，就必须设计失败后重新置 dirty、保留旧 Graph 或重试，否则变化会丢失。当前签名不提供这条错误通道。

## 9. 常见模式与适用边界

| 模式 | 适合 | 不适合 |
|---|---|---|
| 增量 store + 全量重建 | 中等规模状态、正确性优先 | 百万节点且建图昂贵 |
| dirty bit 合批 | 高频突发事件 | 每个事件都必须产生独立审计结果 |
| relevance predicate | 可准确维护依赖集合 | 依赖不可枚举或边沿易遗漏 |
| latest 整体替换 | 下游只读快照 | 下游长期持有并修改节点 |

当全量重建成为瓶颈，再考虑版本化节点、受影响子图、结构共享；不要在没有基准数据时先引入复杂增量算法。

## 10. 源码证据与测试入口

- `internal/controller/state/change_processor.go:NewChangeProcessorImpl`：对象 map、store 配置和 predicate；
- `internal/controller/state/change_processor.go:Process`：dirty 检查、WAF 合并和建图；
- `internal/controller/state/store.go:changeTrackingUpdater`：Upsert/Delete/force 语义；
- `internal/framework/events/first_eventbatch_preparer.go:Prepare`：启动全量快照；
- `internal/controller/handler.go:parseAndCaptureEvent`：普通对象事件与 force 事件分流；
- `internal/controller/state/change_processor_test.go`：捕获、处理和 WAF 合并；
- `internal/framework/events/first_eventbatch_preparer_test.go`：首批读取与错误路径。

## 11. 练习与检查点

1. 为 Demo 写 table-driven test：重复 Upsert 不重建、Delete 存在对象重建、Force 必重建。
2. 增加 `dirtyReasons map[string]struct{}`，输出一次 Process 被哪些输入触发。
3. 假设 `BuildGraph() (*Graph, error)`，设计错误时 dirty/latest 的状态转移。
4. 解释为什么 WAF reconcile event 不应伪装成普通 Kubernetes Upsert。

检查点：看到任何事件驱动派生系统时，你应能画出“原始 store—dirty 判定—批次边界—派生快照—失败恢复”五个部分。

## 延伸阅读

- [[49-EventLoop批处理与状态所有权]]：EventLoop 如何组成批次；
- [[61-Predicate与事件过滤]]：过滤函数的四类事件；
- [[63-Kubernetes对象到Graph领域建模]]：重建的目标模型；
- [[65-Graph到Dataplane再到NGINX]]：新 Graph 的下游副作用。
