---
title: "61 Predicate 与事件过滤"
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

# 61 Predicate 与事件过滤

## 语法

Predicate 在事件进入 reconcile 队列前判断是否值得处理，减少无意义工作；过滤条件必须覆盖真实依赖字段。

**说明性片段：**

```go
type ServicePredicate struct { predicate.Funcs }

func (ServicePredicate) Update(e event.UpdateEvent) bool {
	return relevantChange(e)
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`

**原样源码：**

```go
func (ServiceChangedPredicate) Update(e event.UpdateEvent) bool {
```

Service Update → 比较 Ports/TargetPorts/AppProtocols → false 时丢弃 → true 时进入 Reconcile。

## 相关测试

`internal/framework/controller/predicate/service_test.go`
