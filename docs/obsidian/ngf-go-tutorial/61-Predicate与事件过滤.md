---
title: "61 Predicate 与事件过滤"
tags:
  - nginx-gateway-fabric
  - go-1-26
  - source-analysis
  - tutorial
status: complete
note_type: tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 61 Predicate 与事件过滤

> [!abstract] 本章唯一知识点
> Predicate 在事件进入 reconcile 队列前判断是否值得处理，减少无意义工作；过滤条件必须覆盖真实依赖字段。

## 前置与完成标准

前置：[[60-controller-runtime-Reconciler契约]]。学完应能解释“Predicate 与事件过滤”，并在 NGF 中定位 `ServiceChangedPredicate.Update`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/predicate/service.go · ServiceChangedPredicate.Update（原样摘录）**

```go
func (ServiceChangedPredicate) Update(e event.UpdateEvent) bool {
```

- 定义：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`
- 精简链路：Service Update → 比较 Ports/TargetPorts/AppProtocols → false 时丢弃 → true 时进入 Reconcile。
- 测试佐证：`internal/framework/controller/predicate/service_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

NGF 配置只依赖这些端口字段，因此元数据噪声不触发重建。

> [!warning] 常见误解与迁移边界
> 可复用基于依赖字段的过滤；新增消费者字段必须同步 Predicate 测试。误解是 Predicate 是安全校验，它只是性能/触发语义。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Predicate 与事件过滤不是孤立语法，而是 `ServiceChangedPredicate.Update` 所在边界用来表达约束的工具。**

上一章：[[60-controller-runtime-Reconciler契约]] · 下一章：[[62-Cache-FieldIndexer与查询成本]]

延伸阅读：../ngf-source-analysis/ngf-controller-runtime-interactions-obsidian.md
