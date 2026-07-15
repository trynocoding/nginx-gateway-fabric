---
title: "60 controller-runtime Reconciler 契约"
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

# 60 controller-runtime Reconciler 契约

> [!abstract]
> Reconcile 接收的是可去重的 key，不是原始事件；实现应读取当前状态并向目标状态收敛。controller-runtime v0.24.1 根据 `error/Result` 决定 Forget、延迟重排或限速重试。NGF Reconciler 再把缓存读取结果翻译成内部 Upsert/Delete 事件。

## 学习目标与前置

- 看懂 `Reconcile(context.Context, reconcile.Request) (reconcile.Result, error)`；
- 精确预测 v0.24.1 的 error、RequeueAfter、Requeue 行为；
- 区分 watch 注册、manager 启动和每次 Reconcile 执行；
- 理解缓存读、NotFound 删除语义和 context 取消；
- 追踪 NGF 从 builder.Complete 到内部 eventCh。

前置：[[24-接口的隐式实现]]、[[44-context传递与取消]]、[[57-表驱动子测试与并行测试]]。

## 1. 接口、Request 与 level-based 心智模型

v0.24.1 的核心接口等价于：

```go
type Reconciler interface {
	Reconcile(context.Context, Request) (Result, error)
}

type Request struct {
	types.NamespacedName
}
```

Request 只有 namespace/name，不含 Create/Update/Delete 类型，也不保证“一事件一调用”。workqueue 会合并相同 key；一次调用期间又到来的事件可能只使该 key 再处理一次。正确问题是“这个 key 当前应该是什么状态”，而不是“刚才发生了哪个事件”。

> [!warning]
> Reconciler 必须容忍重复、合并、延迟和缓存短暂陈旧。以增量事件次数为真相会破坏幂等性。

## 2. v0.24.1 `Result/error` 精确矩阵

`reconcile.Result` 含 `Requeue`（已 deprecated）、`RequeueAfter`、`Priority`：

| 返回 | controller 行为 |
|---|---|
| `Result{}, nil` | `Queue.Forget(req)`；等待新事件 |
| `Result{RequeueAfter: d}, nil`，d>0 | Forget 失败历史，d 后 AddAfter |
| `Result{Requeue: true}, nil` | 限速重排；该字段已 deprecated |
| 任意 Result + 普通非 nil error | Result 的重排字段被忽略，限速/退避重排 |
| `reconcile.TerminalError(err)` | 记录错误但不重排 |

这是从 pinned 源码 `pkg/internal/controller/controller.go:reconcileHandler` 验证的框架事实。错误不是“日志附加信息”，会改变队列状态；不要同时返回 error 与 RequeueAfter 期待后者生效。

`Priority` 只在使用 priority queue 时有意义；NGF Reconciler 当前总返回零值 Result。

## 3. 可运行的最小测试（Go 1.26 + controller-runtime v0.24.1）

该 demo 直接调用 Reconciler，验证接口和 Result；它不启动 manager，因此不声称验证 workqueue 退避。

```go
// 可运行测试；Go 1.26.0；controller-runtime v0.24.1
package reconcile_demo

import (
	"context"
	"errors"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

type worker struct{ ready bool }

func (w *worker) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
	if err := ctx.Err(); err != nil {
		return reconcile.Result{}, err
	}
	if req.Name == "broken" {
		return reconcile.Result{}, errors.New("read failed")
	}
	if !w.ready {
		w.ready = true
		return reconcile.Result{RequeueAfter: 10 * time.Millisecond}, nil
	}
	return reconcile.Result{}, nil
}

func TestWorker(t *testing.T) {
	var r reconcile.Reconciler = &worker{}
	req := reconcile.Request{NamespacedName: types.NamespacedName{Namespace: "default", Name: "demo"}}

	first, err := r.Reconcile(t.Context(), req)
	if err != nil || first.RequeueAfter <= 0 {
		t.Fatalf("first=%+v err=%v", first, err)
	}
	second, err := r.Reconcile(t.Context(), req)
	if err != nil || !second.IsZero() {
		t.Fatalf("second=%+v err=%v", second, err)
	}
}
```

```bash
go mod init example.com/reconciledemo
go get sigs.k8s.io/controller-runtime@v0.24.1
gofmt -w reconciler_test.go
go test -race -v .
```

## 4. 注册期与运行期必须分开

NGF 桥接：`ngf:internal/framework/controller/register.go:Register`。

```text
注册期
Register options
  → 注册 FieldIndices
  → NewControllerManagedBy(mgr).Named(name).For(objectType)
  → 可选 WithEventFilter(predicate)
  → ReconcilerConfig{Getter: mgr.GetClient(), EventCh: ...}
  → builder.Complete(NewReconciler(config))

运行期（manager.Start 后）
cache informer 事件
  → predicate
  → handler 把 key 入队/去重
  → worker 调 Reconciler.Reconcile
  → NGF eventCh
```

`Complete` 构建并注册 controller/watch，不会立刻对每个对象调用 Reconcile。manager 启动 cache、等待同步、启动 worker 后才执行。把“注册成功”误当“业务已运行”会导致启动问题难排查。

## 5. NGF Reconciler 的生产路径

`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`：

1. 从框架 context 取 logger；
2. 可选 `NamespacedNameFilter` 在 Get 前过滤 key；
3. `mustCreateNewObject` 依据 ObjectType/OnlyMetadata 创建接收对象；
4. `Getter.Get(ctx, req.NamespacedName, obj)` 读取；
5. NotFound → `obj=nil` → 构造 `events.DeleteEvent`；
6. 成功 → 构造 `events.UpsertEvent{Resource: obj}`；
7. select：context 已取消则不发送，否则向 EventCh 发送；
8. 返回 `Result{}, nil`。

`Getter` 是 `client.Reader.Get` 的窄接口；Register 注入 `mgr.GetClient()`。manager 默认 Client 的读取通常来自本地 cache，写入直达 API server。这里 Reconciler 只读且不写 Kubernetes 对象，它把资源状态交给后续 EventLoop/Graph 层。

### NotFound 为什么是删除，不是错误重试

key 仍在队列但当前对象不存在，正是 level-based 删除观察。返回 error 会制造无意义退避重试；NGF 把它翻译成内部 DeleteEvent，让 ClusterState 删除旧对象。

普通 Get error（网络/cache/解码等）直接返回 error，框架 v0.24.1 会限速重排。此时不发送事件，避免把“读取失败”误当“对象删除”。

### context 取消

发送 EventCh 前 select context，使 shutdown 不会永久阻塞。当前实现若 context 在 Get 后取消，会返回成功空 Result，不重排；manager 正在退出时这是合理清理路径。若是仍在运行的调用方主动取消，不能据此假定事件最终被处理。

## 6. 测试如何固定契约

`internal/framework/controller/reconciler_test.go` 以 FakeGetter 和无缓冲 eventCh 验证：

- Get 成功 → UpsertEvent + 空 Result/nil error；
- Kubernetes NotFound → DeleteEvent + 成功；
- 普通 Get error → eventCh 无消息，原 error 返回；
- filter 拒绝 → 不调用业务事件路径；
- 已取消 context → upsert/delete 均不阻塞、不发事件。

测试直接调用 Reconcile，只验证项目实现；框架 Result→队列行为由 pinned controller-runtime 源码/上游测试支持，两层证据不要混写。

## 7. 常用 Reconcile 模式

### 读取—比较—写入

读取主对象和依赖对象，计算 desired state，创建/patch 子资源；所有操作可重复。

### NotFound 清理外部资源

主对象缺失时清理仍存在的外部状态；若依赖 finalizer，要在对象删除前的 deletionTimestamp 路径处理。

### 外部系统轮询

没有 watch 的外部状态可成功后 `RequeueAfter`，不要用 error 表示“尚未完成”。

### 失败重试

临时失败返回包装 error；永久无意义重试可转换为状态并成功返回，或谨慎使用 TerminalError。

## 8. 误区与迁移边界

- Request 不含事件类型；不要在 Reconcile 依赖 old/new object；
- cache 读取可能短暂陈旧；写后立即读不保证 read-your-write；
- error 与 RequeueAfter 同返时，v0.24.1 忽略 Result 重排；
- `Requeue` 已 deprecated，新代码使用明确 `RequeueAfter`；
- NGF 的 Reconciler 是“对象→内部事件”适配器，不是所有 controller 都应照搬；普通 operator 可直接收敛子资源；
- EventCh 无缓冲带来背压；context select 是退出安全边界。

## 9. 练习与检查点

1. Get 返回 NotFound 时为何不返回 error？缺失是当前状态，NGF 需发 DeleteEvent 收敛内部状态。
2. `(RequeueAfter: 1s, err)` 哪个生效？error；Result 重排被忽略。
3. Register 完成后 Reconcile 是否已运行？否，需 manager 启动、cache/source 产生 key、worker 消费。
4. 如何验证 cache 与 API server 权威值差异？必要时使用 `mgr.GetAPIReader()` 做 live read，并明确成本与一致性需求。

## 源码证据索引

- 项目接口：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`。
- 注册桥：`ngf:internal/framework/controller/register.go:Register`。
- 测试：`ngf:internal/framework/controller/reconciler_test.go`。
- pinned 接口：`controller-runtime@v0.24.1/pkg/reconcile/reconcile.go`。
- 队列分支：`controller-runtime@v0.24.1/pkg/internal/controller/controller.go:reconcileHandler`。
- cache-backed client：`controller-runtime@v0.24.1/pkg/client/client.go`、`pkg/cluster/cluster.go`。

上一章：[[59-Counterfeiter-fake与可测试注入]] · 下一章：[[61-Predicate与事件过滤]] · 延伸：[[64-ChangeProcessor幂等与增量重建]]
