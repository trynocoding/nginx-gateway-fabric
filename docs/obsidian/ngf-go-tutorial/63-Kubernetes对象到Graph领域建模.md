---
title: "63 Kubernetes 对象到 Graph 的领域建模"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: mechanism-tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 63 Kubernetes 对象到 Graph 的领域建模

> [!abstract]
> Kubernetes 对象是面向存储和 API 兼容性的“事实”；Graph 是面向网关行为的“解释结果”。NGF 的 `BuildGraph` 把 `ClusterState` 中的原始对象，变成包含引用、附着、有效性和状态条件的派生领域模型，供配置生成与状态计算共同消费。

## 学习目标与前置

- 用 struct、map、指针和组合表达领域模型；
- 区分原始状态、派生状态、持久状态；
- 理解“保留无效对象”为什么比直接丢弃更有价值；
- 读懂 `BuildGraph` 的阶段顺序和依赖；
- 判断 Graph 的所有权、并发和不可变边界。

前置：[[13-map-comma-ok与缺失值]]、[[22-值与指针接收者方法集]]、[[64-ChangeProcessor幂等与增量重建]]。

## 1. 从 Go 基础数据结构开始

领域模型通常由四种结构组成：

```go
type Key struct {
	Namespace string
	Name      string
}

type RawRoute struct {
	Key        Key
	GatewayRef Key
	BackendRef Key
}

type Route struct {
	Source   *RawRoute
	Attached bool
	Valid    bool
	Reason   string
}

type Graph struct {
	Routes map[Key]*Route
}
```

- struct 把属于同一概念的字段组合起来；
- `map[Key]*Route` 用稳定身份做查找，平均查找成本是 O(1)；
- `Source` 保留原始对象，便于生成状态和定位用户输入；
- `Attached/Valid/Reason` 是计算结果，不应反写到原始对象；
- 指针让多个派生索引引用同一个节点，但也意味着调用方可以修改它。

Kubernetes 常用 `types.NamespacedName` 表示“命名空间 + 名称”。若身份还包含资源种类、Listener section 或 Group/Kind，就要定义更强的 key，不能把不同对象误合并。

## 2. 三类状态不要混淆

| 状态 | 例子 | 生命周期 | 谁负责 |
|---|---|---|---|
| 原始观察状态 | Gateway、Route、Service | 随 watch 事件变化 | `ClusterState` |
| 派生领域状态 | Route 是否附着、引用是否有效 | 每次建图重新计算 | `Graph` |
| 持久 API 状态 | `status.conditions` | 写回 API server | status queue/controller |

Graph 不是 API server 的镜像，也不是数据库；重启后可以从对象重新构建。Graph 中的条件可作为写 status 的输入，但 Graph 本身没有持久化。

## 3. 完整可运行 Demo：保留无效节点

下面的程序把原始 Gateway/Route 转为 Graph。它刻意保留无效 Route：配置生成可以跳过它，状态生成却仍能报告原因。

```go
package main

import "fmt"

type Key struct{ Namespace, Name string }

type RawGateway struct{ Key Key }

type RawRoute struct {
	Key        Key
	GatewayRef Key
	BackendRef Key
}

type Route struct {
	Source   *RawRoute
	Attached bool
	Valid    bool
	Reason   string
}

type Graph struct {
	Gateways map[Key]*RawGateway
	Routes   map[Key]*Route
	Backends map[Key]struct{}
}

func BuildGraph(gateways []RawGateway, routes []RawRoute, backends []Key) *Graph {
	g := &Graph{
		Gateways: make(map[Key]*RawGateway, len(gateways)),
		Routes:   make(map[Key]*Route, len(routes)),
		Backends: make(map[Key]struct{}, len(backends)),
	}
	for i := range gateways {
		gateway := &gateways[i]
		g.Gateways[gateway.Key] = gateway
	}
	for _, key := range backends {
		g.Backends[key] = struct{}{}
	}
	for i := range routes {
		raw := &routes[i]
		node := &Route{Source: raw}
		_, node.Attached = g.Gateways[raw.GatewayRef]
		if !node.Attached {
			node.Reason = "GatewayNotFound"
		} else if _, ok := g.Backends[raw.BackendRef]; !ok {
			node.Reason = "BackendNotFound"
		} else {
			node.Valid = true
			node.Reason = "Accepted"
		}
		g.Routes[raw.Key] = node
	}
	return g
}

func main() {
	ns := "shop"
	gw := Key{ns, "public"}
	okRoute := Key{ns, "checkout"}
	badRoute := Key{ns, "legacy"}
	g := BuildGraph(
		[]RawGateway{{Key: gw}},
		[]RawRoute{
			{Key: okRoute, GatewayRef: gw, BackendRef: Key{ns, "checkout-svc"}},
			{Key: badRoute, GatewayRef: gw, BackendRef: Key{ns, "missing-svc"}},
		},
		[]Key{{ns, "checkout-svc"}},
	)
	for _, key := range []Key{okRoute, badRoute} {
		r := g.Routes[key]
		fmt.Printf("%s: attached=%v valid=%v reason=%s\n",
			key.Name, r.Attached, r.Valid, r.Reason)
	}
}
```

运行：

```bash
go run main.go
```

预期输出：

```text
checkout: attached=true valid=true reason=Accepted
legacy: attached=true valid=false reason=BackendNotFound
```

### Demo 中值得迁移的模式

1. **两阶段处理**：先建立 Gateway/Backend 索引，再解析 Route 引用。
2. **原始对象与派生节点分离**：不在 `RawRoute` 上塞验证结果。
3. **无效对象仍入图**：控制面需要为错误输入生成可观察状态。
4. **稳定 key**：不要把 slice 下标或指针地址当业务身份。

> [!warning]
> Demo 为讲解所有权，保存了输入 slice 元素的指针。生产代码必须保证输入在 Graph 生命周期内不被并发修改；跨 goroutine 共享前可深拷贝或建立严格的单写者协议。

## 4. NGF 的 BuildGraph 分阶段做什么

源码入口：`internal/controller/state/graph/graph.go:BuildGraph`。

在 revision `918d0fa7`，主顺序可压缩为：

1. 处理 GatewayClass；若目标类存在但本控制器不是 winner，返回空 Graph；
2. 处理 Gateway、NginxProxy，并建立 GatewayClass/Gateway 节点；
3. 创建资源与 ReferenceGrant resolver；
4. 附着 ListenerSet；
5. 构建 BackendTLSPolicy、SnippetsFilter、AuthenticationFilter；
6. 构建 L7/L4 Route，解析 backend 引用并绑定 Listener；
7. 计算被引用的 Namespace、Service、Secret、ConfigMap 等集合；
8. 处理 WAF 输入；
9. 最后处理和附着 Policy，因为 Policy 依赖前面形成的图状态；
10. 校验 ExternalAuth 冲突，返回完整 Graph。

顺序是依赖关系，不是排版偏好。例如 Route 绑定前必须有 Gateway/Listener；Policy 附着前必须知道目标节点；引用集合又会影响后续事件过滤。

## 5. Graph 不只是邻接表

`internal/controller/state/graph/graph.go:Graph` 包含 GatewayClass、Gateways、Routes、L4Routes，也包含：

- 被忽略的 GatewayClass；
- 被引用的 Secret、Namespace、Service、ConfigMap、InferencePool；
- NginxProxy、ListenerSet、各类 Filter 和 Policy；
- WAF 资源及 Plus/PLM Secret；
- 供状态与配置生成使用的派生关系。

因此它更接近“编译器中间表示（IR）”：原始 YAML 是源语言，Graph 完成名称解析、类型/引用检查和附着，dataplane configuration 是目标模型。

一个特别重要的设计是：`ReferencedSecrets` 可以保留“当前不存在但已被引用”的 key。这样 Secret 稍后创建时，predicate 能判断该事件会改变 Graph。若只记录已经存在的 Secret，就会漏掉“从缺失变为存在”的边沿。

## 6. 验证器为什么在建图阶段出现

`BuildGraph` 接收 `validation.Validators`。建图不仅相信 CRD schema，还会执行数据面或通用再验证：

- CRD schema 可能被管理员改动；
- 单对象字段合法，不代表跨对象引用和组合合法；
- 某些配置只有交给数据面语义检查才知道是否可生成。

验证失败通常应进入节点条件，使用户看到原因；不能一律把对象从图里删除，否则 status 层不知道它曾被处理。

## 7. 所有权与并发边界

`BuildGraph` 返回一个新 Graph，但“新 Graph”不等于递归深拷贝：节点常保留 `Source *KubernetesType`。当前架构由 `ChangeProcessor` 串行持有 `ClusterState` 与 `latestGraph`，事件批次在锁内建图。

迁移到其他项目时，不要自动推出“Graph 天生 immutable”。安全选择有三种：

- 单 goroutine/单写者拥有 Graph；
- 构建完成后只读，更新时整体替换；
- 对外返回深拷贝或只读接口。

`GetLatestGraph` 返回指针，因此调用者若修改内部 map，会破坏协议。这里的只读是一条架构约定，不是 Go 类型系统保证。

## 8. 失败模式与设计检查

| 失败模式 | 后果 | 修正 |
|---|---|---|
| 解析 Route 前未建 Gateway 索引 | 合法引用误判缺失 | 按依赖拓扑分阶段 |
| 直接丢弃无效对象 | 无法写详细 status | 保留节点和 reason |
| key 只有 name | 跨 namespace 冲突 | 使用 namespaced/typed key |
| 派生字段写回缓存对象 | 数据竞争、污染 informer cache | 分离 Source 与 node |
| 把 Graph 当持久真相 | 重启/事件后状态漂移 | 始终可由 ClusterState 重建 |

## 9. 源码证据与测试入口

- `internal/controller/state/graph/graph.go:Graph`：领域模型字段集合；
- `internal/controller/state/graph/graph.go:BuildGraph`：完整建图编排；
- `internal/controller/state/validation/validation.go:Validators`：建图验证契约；
- `internal/controller/state/graph/graph_test.go`：Graph 顶层行为；
- `internal/controller/state/graph/multiple_gateways_test.go`：多 Gateway 场景；
- `internal/controller/state/graph/gateway/gatewayclass_test.go`：GatewayClass 选择与条件。

## 10. 练习与检查点

1. 给 Demo 增加 `ReferenceGrant`：跨 namespace 时没有 grant 就标记 `RefNotPermitted`。
2. 给 `Graph` 增加 `RoutesByGateway map[Key][]Key`，说明它是派生索引还是权威数据。
3. 写测试证明缺失 backend 创建后，重建 Graph 会从 `BackendNotFound` 变为 `Accepted`。
4. 回答：为什么“返回新 Graph”仍不能证明线程安全？

检查点：你应能从一个新 CRD 出发，设计原始存储、稳定 key、派生节点、引用索引、状态条件和建图阶段，而不是把所有判断塞进 Reconcile。

## 延伸阅读

- [[64-ChangeProcessor幂等与增量重建]]：谁维护 ClusterState、何时触发重建；
- [[65-Graph到Dataplane再到NGINX]]：Graph 如何成为 NGINX 文件；
- [[13-map-comma-ok与缺失值]]：索引和缺失语义；
- [[46-Mutex-RWMutex与临界区]]：Graph 所有权与锁。
