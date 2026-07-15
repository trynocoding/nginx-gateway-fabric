---
title: "58 Ginkgo/Gomega 的行为测试组织"
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

# 58 Ginkgo/Gomega 的行为测试组织

> [!abstract] 本章唯一知识点
> Describe/Context/It 按行为层次组织，BeforeEach 建立场景；断言表达可观察结果而非实现细节。

## 前置与完成标准

前置：[[57-表驱动子测试与并行测试]]。学完应能解释“Ginkgo/Gomega 的行为测试组织”，并在 NGF 中定位 `Reconciler.Reconcile`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/reconciler.go · Reconciler.Reconcile（原样摘录）**

```go
func (r *Reconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
```

- 定义：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`
- 精简链路：Ginkgo 场景启动 Reconcile → fake Getter/EventCh 控制输入 → Gomega 断言 Upsert/Delete/取消结果。
- 测试佐证：`internal/framework/controller/reconciler_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

异步 channel 和多分支契约用行为层次比巨型表更易读。

> [!warning] 常见误解与迁移边界
> 可用于 exported interface/异步行为；简单纯函数仍优先标准 testing。误解是 BDD 只是在测试名字上加自然语言。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Ginkgo/Gomega 的行为测试组织不是孤立语法，而是 `Reconciler.Reconcile` 所在边界用来表达约束的工具。**

上一章：[[57-表驱动子测试与并行测试]] · 下一章：[[59-Counterfeiter-fake与可测试注入]]

延伸阅读：docs/developer/testing.md
