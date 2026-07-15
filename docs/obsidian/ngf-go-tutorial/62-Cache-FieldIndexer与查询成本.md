---
title: "62 Cache、FieldIndexer 与查询成本"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: framework-tutorial
go_version: "1.26.0"
framework_version: "sigs.k8s.io/controller-runtime v0.24.1"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 62 Cache、FieldIndexer 与查询成本

> [!abstract]
> controller-runtime manager 的默认 Client 读本地 cache、写 API server；cache 是观察副本，不是权威存储。FieldIndexer 在对象进入/更新 cache 时预计算键，使 `MatchingFields` 查询从全量扫描变为索引查找，代价是内存、维护和注册一致性。

## 学习目标与前置

- 区分 Cache、Client、APIReader 与 API server；
- 写 IndexerFunc、注册 IndexField、用 MatchingFields 查询；
- 分析无索引 List 的时间/网络/内存成本；
- 处理 cache sync、stale read、write-after-read；
- 识别 NGF PodIP 索引当前“已注册但无生产查询”的负证据。

前置：[[13-map-comma-ok与缺失值]]、[[60-controller-runtime-Reconciler契约]]。

## 1. 四个角色

| 角色 | 责任 | 一致性/成本 |
|---|---|---|
| Kubernetes API server | 权威持久状态 | 网络请求、服务端语义 |
| controller-runtime Cache | informer 的本地对象副本与索引 | 最终一致、内存换读取 |
| manager Client | 默认读 cache、写直达 API server | 写后读可能暂时旧 |
| APIReader | 不经过 cache 的 live reader | 更新鲜但增加 API 压力 |

v0.24.1 `pkg/client/client.go` 明确：配置 Cache.Reader 时 Get/List 可走 cache，Create/Update/Delete/Patch 直接到 API server；可按 GVK DisableFor 或让 unstructured 绕过 cache。

> [!warning]
> cache 不是事务快照。多个对象来自不同 watch 时点；不能把一次 List 当跨资源强一致读。

## 2. FieldIndexer 接口

```go
type IndexerFunc func(client.Object) []string

type FieldIndexer interface {
	IndexField(ctx context.Context, obj client.Object, field string, extract IndexerFunc) error
}
```

extract 对每个对象返回零个、一个或多个非 namespace key。controller-runtime 自动处理 namespace 维度；查询时 equality 表示至少一个 index key 匹配。

注册和查询必须共享三个契约：对象 GVK、field 字符串、键规范化。任一不一致会返回错误或查不到对象。

## 3. 可独立运行的最小索引 demo（Go 1.26）

这个纯 Go demo 展示索引算法，不冒充 controller-runtime cache：

```go
// 可运行程序；Go 1.26.0
package main

import "fmt"

type EndpointSlice struct {
	Name        string
	ServiceName string
}

func buildIndex(items []EndpointSlice) map[string][]EndpointSlice {
	index := make(map[string][]EndpointSlice)
	for _, item := range items {
		if item.ServiceName == "" {
			continue
		}
		index[item.ServiceName] = append(index[item.ServiceName], item)
	}
	return index
}

func main() {
	items := []EndpointSlice{
		{Name: "api-a", ServiceName: "api"},
		{Name: "web-a", ServiceName: "web"},
		{Name: "api-b", ServiceName: "api"},
	}
	index := buildIndex(items)
	fmt.Println(len(index["api"]), index["api"][0].Name, index["api"][1].Name)
}
```

```bash
gofmt -w main.go
go run .
# 2 api-a api-b
```

全量过滤每次 O(n)；索引构建/更新付出维护成本后，查询接近 O(匹配数 + map 查找)。controller-runtime 实际实现还有 namespace key、informer store 与锁，不能由这个 demo 推导精确复杂度常数。

## 4. NGF 的注册封装

`ngf:internal/framework/controller/register.go:AddIndex`：

```text
上层 ctx
  → context.WithTimeout(2 minutes)
  → mgr.GetFieldIndexer().IndexField(objectType, field, indexerFunc)
  → 错误包装对象类型与字段名
```

`controller.Register` 的 `WithFieldIndices` 会在 builder.Complete 前逐项 AddIndex。索引注册属于构建/启动配置；运行查询不能临时“假设索引存在”。注册失败会让 controller 注册失败，而不是退化成静默全表扫描。

## 5. 活跃实例：EndpointSlice 按 Service 查询

索引定义：`ngf:internal/framework/controller/index/endpointslice.go`：

```text
field = "k8sServiceName"
ServiceNameIndexFunc(EndpointSlice)
  → 读取 label kubernetes.io/service-name
  → 空名返回 nil
  → 返回 []string{name}
```

注册：`internal/controller/manager.go:registerControllers` 为 EndpointSlice controller 传 `WithFieldIndices(index.CreateEndpointSliceFieldIndices())`。

消费：`internal/controller/state/resolver/resolver.go:ServiceResolverImpl.Resolve`：

```go
reader.List(ctx, &endpointSliceList,
	client.MatchingFields{index.KubernetesServiceNameIndexField: svcNsName.Name},
	client.InNamespace(svcNsName.Namespace),
)
```

查询只取一个 Service 在一个 namespace 的 EndpointSlices，随后解析 ready endpoints。这里索引直接缩小 Graph→Dataplane 构建期间的读取成本。

## 6. PodIP 索引的当前负证据

`internal/framework/controller/index/pod.go:PodIPIndexFunc` 将 `Pod.Status.PodIP` 返回为 key；`internal/controller/manager.go:createManager` 把它注册为 `status.podIP`，注释说供 gRPC token validator 验证连接来源。

但在 revision `918d0fa7` 的生产源码 census 中：

- 没有 `client.MatchingFields{"status.podIP": ...}` 查询；
- 当前 `grpc/interceptor/interceptor.go` token 验证按 namespace + app label List Pod，再统计 Running Pod；
- 只有 interceptor 测试 fake client 配置了该 index。

因此能确认“索引已注册”，不能声称“生产查询正在使用”。这可能是历史遗留、预留或间接需求；没有历史证据时不推断作者意图。维护者若删除它，应先检查 cache/watch、测试和安全设计，而非只依据文本搜索。

## 7. stale、同步与权威状态

### 启动同步

manager 在启动 controller 前等待相关 cache sync；若 sync 失败，不能假定本地对象完整。`WaitForCacheSync` 是生命周期边界。

### 写后读

Client.Update 成功只证明 API server 接受写入；cache watch 传播有延迟。立即 Get 可能读旧 ResourceVersion。可继续使用返回对象、等待观察条件，或在必须 live 的窄路径使用 APIReader。

### 缺失 informer

v0.24.1 cache 默认可能为新请求类型启动 informer；`ReaderFailOnMissingInformer=true` 则返回 `ErrResourceNotCached`。无意 List 新类型可能带来全量 cache 与 RBAC/内存成本。

### 索引 stale

索引随 informer 对象更新，不会比 cache 更权威。它加速的是当前 cache 视图查询，不改善新鲜度。

## 8. 索引函数设计准则

- 纯函数、快速、不做 I/O；
- 对错误对象类型可 panic 以暴露注册错误，NGF index 函数如此；
- 缺失字段返回 nil，而非无意义空 key，除非查询确需空值；
- key 规范化与查询完全一致（大小写、前后缀、namespace）；
- 多值索引要理解 equality 任一匹配；
- 索引字段名是内部协议常量，不必是真实 Kubernetes struct path。

## 9. 成本与选择

| 方案 | 读取成本 | 维护成本 | 适用 |
|---|---|---|---|
| API server List + selector | 网络/服务端 | RBAC、API 压力 | cache 外权威查询 |
| cache 全 List 后过滤 | O(n) 本地 | 简单 | 小集合/低频 |
| cache FieldIndexer | 索引查找 + 匹配结果 | 内存、注册、同步契约 | 高频反向查询 |
| 独立业务 map | 最快但双份状态 | 一致性最难 | 明确单一所有者的派生状态 |

不要为只调用一次的小列表先建索引；也不要在每个 reconcile 扫描数万对象。用对象规模、频率和 profile 决定。

## 10. 练习与检查点

1. FieldIndexer 能提供强一致读吗？不能，只索引 cache 当前视图。
2. 为什么写后立即 cache Get 可能旧？写直达 API server，informer watch 尚未传播。
3. EndpointSlice 索引的 field 是真实字段路径吗？不是必须；`k8sServiceName` 是双方约定的内部索引名。
4. PodIPIndexFunc 当前能证明什么？注册与测试存在；不能证明生产 MatchingFields 查询存在。

## 源码证据索引

- pinned cache/client：`controller-runtime@v0.24.1/pkg/client/client.go`、`pkg/cache/cache.go`、`pkg/cluster/cluster.go`。
- NGF 注册：`ngf:internal/framework/controller/register.go:AddIndex`、`WithFieldIndices`。
- 活跃索引：`ngf:internal/framework/controller/index/endpointslice.go`。
- 活跃查询：`ngf:internal/controller/state/resolver/resolver.go:ServiceResolverImpl.Resolve`。
- PodIP 负证据：`ngf:internal/framework/controller/index/pod.go`、`internal/controller/manager.go:createManager`、`grpc/interceptor/interceptor.go`。
- 测试：`index/endpointslice_test.go`、`index/pod_test.go`、`register_test.go`、resolver 测试。

上一章：[[61-Predicate与事件过滤]] · 下一章：[[63-Kubernetes对象到Graph领域建模]] · 延伸：[[64-ChangeProcessor幂等与增量重建]]
