---
title: "61 Predicate 与事件过滤"
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

# 61 Predicate 与事件过滤

> [!abstract]
> Predicate 在事件交给 handler、生成 reconcile key 之前返回 true/false。它能降低队列和重建成本，却会真正丢掉被拒绝的触发；条件漏掉任何影响输出的字段，就可能让状态永久陈旧直到另一个事件碰巧唤醒。

## 学习目标与前置

- 实现 Create/Update/Delete/Generic 四个方法；
- 理解嵌入 `predicate.Funcs` 的默认 true 行为；
- 区分全局 `WithEventFilter` 与单 watch predicates；
- 设计 update old/new 比较和 nil/type 失败策略；
- 审计 NGF Service/Secret predicate 的过滤风险。

前置：[[16-for-range整数range与迭代]]、[[60-controller-runtime-Reconciler契约]]。

## 1. v0.24.1 接口

```go
type Predicate interface {
	Create(event.CreateEvent) bool
	Delete(event.DeleteEvent) bool
	Update(event.UpdateEvent) bool
	Generic(event.GenericEvent) bool
}
```

事件对象：Create/Delete/Generic 有 `Object`，Update 有 `ObjectOld/ObjectNew`。true 只表示继续到 event handler；还不保证一定立即执行 Reconcile，队列会去重和调度。

`predicate.Funcs` 是四个可选函数字段；v0.24.1 中未设置的函数返回 **true**。NGF 常通过嵌入它，只覆写关心的方法：

```go
type ServiceChangedPredicate struct {
	predicate.Funcs
}
```

因此它覆写 Update，但 Create/Delete/Generic 从嵌入的 Funcs 得到默认 true。这个默认值必须从 pinned 源码确认，不能凭印象写成 false。

## 2. 四类事件的设计问题

| 方法 | 常见判断 | 误过滤后果 |
|---|---|---|
| Create | 类型、namespace/name、标签/注解 | 新对象永不入内部状态 |
| Update | old/new 中所有相关字段 | 修改未触发，配置陈旧 |
| Delete | tombstone 对象身份 | 旧状态残留 |
| Generic | 外部主动发送的对象 | 手动/周期触发失效 |

Predicate 应廉价、纯、无网络 I/O。复杂依赖查询应留给 Reconcile；在 predicate 里读 API 既放大事件成本，也引入一致性与失败语义难题。

## 3. 可运行最小 demo（Go 1.26 + controller-runtime v0.24.1）

```go
// 可运行程序；Go 1.26.0；controller-runtime v0.24.1
package main

import (
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

type LabelPredicate struct {
	predicate.Funcs
}

func (LabelPredicate) Update(e event.UpdateEvent) bool {
	if e.ObjectOld == nil || e.ObjectNew == nil {
		return false
	}
	return e.ObjectOld.GetLabels()["enabled"] != e.ObjectNew.GetLabels()["enabled"]
}

func main() {
	oldPod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{"enabled": "false"}}}
	newPod := oldPod.DeepCopy()
	newPod.Labels["enabled"] = "true"

	p := LabelPredicate{}
	fmt.Println("create", p.Create(event.CreateEvent{Object: oldPod})) // embedded default true
	fmt.Println("update", p.Update(event.UpdateEvent{ObjectOld: oldPod, ObjectNew: newPod}))
	fmt.Println("delete", p.Delete(event.DeleteEvent{Object: newPod})) // embedded default true
}
```

```bash
go mod init example.com/predicatedemo
go get sigs.k8s.io/controller-runtime@v0.24.1
gofmt -w main.go
go run .
# create true
# update true
# delete true
```

## 4. 过滤在运行链的位置

v0.24.1 builder：

```text
cache informer event
  → source.Kind
  → 全局 predicates + For/Owns/Watches 局部 predicates
  → event handler（如 EnqueueRequestForObject）
  → workqueue key 去重
  → Reconcile
```

`WithEventFilter(p)` 把 p 加到 builder 的 globalPredicates，对 For/Owns/Watches 的所有 watched objects 生效；因此 predicate 必须能处理所有这些类型。`WatchesRawSource` 不遵守 WithEventFilter，这是 pinned builder 注释明确的例外。

NGF `controller.Register` 只有 `For(objectType)`，有配置时调用 `builder.WithEventFilter(cfg.k8sPredicate)`，所以过滤该 controller 的主对象事件。

## 5. NGF Service predicate

`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`：

1. old/new nil → false；
2. 任一不是 `*corev1.Service` → false；
3. Ports 长度不同 → true；
4. 把每个 Port/TargetPort/AppProtocol 归一成 `portInfo` set；
5. 比较集合，忽略顺序；
6. 相同返回 false。

它刻意忽略 ClusterIP、selector、metadata 等变化，因为当前 controller 只关心端口映射相关字段。Create/Delete 仍为 true，确保新增/删除 Service 可进入内部 EventLoop。

### 丢事件风险怎么审计

若未来 dataplane 输出开始依赖 Service 的新字段（例如某 annotation/trafficDistribution），但 Predicate 未同步，Update 会被丢弃。修改消费者时必须反向检查 filter：

```text
新字段进入 Graph/Dataplane
  → controller 是否 watch 对象
  → Predicate Update 是否包含该字段
  → ChangeProcessor 是否认为对象 referenced/changed
  → 测试是否覆盖仅该字段变化
```

## 6. NGF Secret predicate 对照

`SecretNamePredicate` 明确实现四个方法，Create/Update/Delete/Generic 都：

- nil → false；
- 类型不是 Secret → false；
- namespace 与允许 names 匹配才 true。

这是身份过滤而非字段变化过滤。Update 只看 new object，因为允许集合由外部配置固定；只要目标 Secret 更新，后续 Reconcile/事件层再读取内容。

另一个 `PLMStatusChangedPredicate` 选择 fail-closed：unstructured status 字段类型异常时返回 true，让 Reconcile 有机会暴露/恢复；Service 类型断言失败则 false，因为注册的对象类型不应错。失败策略取决于“漏掉事件”和“多做一次 reconcile”哪个风险更高。

## 7. 常用模式

### GenerationChanged

忽略只改 status/metadata 的更新，适合输出只依赖 spec；但 annotation、finalizer 或外部 status 依赖会被漏掉。

### ResourceVersionChanged

过滤 resync 的相同版本事件，但仍允许任何真实写入；成本低、筛选较粗。

### 精确字段比较

如 Service ports，节省最多，但维护 blast radius 最大；应有“每个相关字段单独变化”的测试。

### 身份 allowlist

如 SecretNamePredicate，用 namespace/name 限制 controller 只处理配置资源。

## 8. 失败、边界与恢复

- Predicate 返回 false 没有 error 通道，也不会自动重试；
- cache resync 可能产生 old/new 相同对象，精确 diff 会过滤；不能把 resync 当漏事件恢复保证；
- delete tombstone/对象不完整时需保守策略，否则内部状态残留；
- expensive DeepEqual 每事件执行，需 profile；先投影出关心字段通常更清楚；
- 多个 predicates 通常是 AND 关系，任一 false 即过滤；
- 需要周期性修复时用 RequeueAfter/独立 source，不要故意放宽所有 predicate。

## 9. 测试策略

对 Update predicate 至少覆盖：old/new nil、错误类型、长度变化、每个相关字段变化、无关字段变化、顺序变化、nil/空归一语义。`internal/framework/controller/predicate/service_test.go` 是直接锚点；`register_test.go` 确认 predicate 进入 Register builder 配置。

## 10. 练习与检查点

1. 嵌入 `predicate.Funcs` 只覆写 Update，Create 默认什么？v0.24.1 返回 true。
2. Predicate false 后框架会重试吗？不会；事件在 handler/入队前被过滤。
3. WithEventFilter 是否影响 WatchesRawSource？不影响，pinned builder 注释明确说明。
4. 新增输出依赖字段时要同步什么？predicate 投影/比较、Graph/change tracking、测试与文档。

## 源码证据索引

- pinned 接口/default：`controller-runtime@v0.24.1/pkg/predicate/predicate.go`。
- pinned 注册位置：`controller-runtime@v0.24.1/pkg/builder/controller.go:WithEventFilter`、`doWatch`。
- NGF 桥：`ngf:internal/framework/controller/register.go:Register`。
- 字段过滤：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`。
- 四事件过滤：`ngf:internal/framework/controller/predicate/secret.go:SecretNamePredicate`。
- 测试：相邻 `service_test.go`、`secret_test.go`、`register_test.go`。

上一章：[[60-controller-runtime-Reconciler契约]] · 下一章：[[62-Cache-FieldIndexer与查询成本]]
