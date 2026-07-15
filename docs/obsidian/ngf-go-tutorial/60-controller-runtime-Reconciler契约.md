---
title: "60 controller-runtime Reconciler 契约"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 60 controller-runtime Reconciler 契约

## 语法

Reconcile 接受 namespaced name，返回 result/error；controller-runtime 负责排队与重试，NGF 的实现只翻译事件。

**说明性片段：**

```go
func (r *Reconciler) Reconcile(
	ctx context.Context,
	req reconcile.Request,
) (reconcile.Result, error) {
	// 读取对象并产生内部事件
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`

**原样源码：**

```go
func (r *Reconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
```

watch/queue → Reconcile Get 对象 → UpsertEvent/DeleteEvent → eventCh；Getter 非 NotFound 错误返回并由框架重试。

## 相关测试

`internal/framework/controller/reconciler_test.go`
