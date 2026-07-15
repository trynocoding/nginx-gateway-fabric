---
title: "60 controller-runtime Reconciler 契约"
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

# 60 controller-runtime Reconciler 契约

> [!abstract] 本章唯一知识点
> Reconcile 接受 namespaced name，返回 result/error；controller-runtime 负责排队与重试，NGF 的实现只翻译事件。

## 前置与完成标准

前置：[[59-Counterfeiter-fake与可测试注入]]。学完应能解释“controller-runtime Reconciler 契约”，并在 NGF 中定位 `Reconciler.Reconcile`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/reconciler.go · Reconciler.Reconcile（原样摘录）**

```go
func (r *Reconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
```

- 定义：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`
- 精简链路：watch/queue → Reconcile Get 对象 → UpsertEvent/DeleteEvent → eventCh；Getter 非 NotFound 错误返回并由框架重试。
- 测试佐证：`internal/framework/controller/reconciler_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

业务图构建不放在 Reconcile 中，避免每个资源控制器复制逻辑，并交给 EventLoop 批处理。

> [!warning] 常见误解与迁移边界
> 可复用薄 Reconciler 架构需配套可靠事件循环和首批快照。误解是成功 Reconcile 就代表 NGINX 已更新。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**controller-runtime Reconciler 契约不是孤立语法，而是 `Reconciler.Reconcile` 所在边界用来表达约束的工具。**

上一章：[[59-Counterfeiter-fake与可测试注入]] · 下一章：[[61-Predicate与事件过滤]]

延伸阅读：../ngf-source-analysis/ngf-controller-runtime-interactions-obsidian.md
