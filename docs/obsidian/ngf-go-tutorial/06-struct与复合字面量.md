---
title: "06 struct 与复合字面量"
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

# 06 struct 与复合字面量

> [!abstract] 本章唯一知识点
> struct 聚合有名字的字段；带字段名的复合字面量能抵抗字段顺序变化。

## 前置与完成标准

前置：[[05-类型定义别名与显式转换]]。学完应能解释“struct 与复合字面量”，并在 NGF 中定位 `ReconcilerConfig`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/reconciler.go · ReconcilerConfig（原样摘录）**

```go
type ReconcilerConfig struct {
```

- 定义：`ngf:internal/framework/controller/reconciler.go:ReconcilerConfig`
- 精简链路：Register 组装 ReconcilerConfig → NewReconciler 保存 cfg → Reconcile 读取依赖和策略。
- 测试佐证：`internal/framework/controller/reconciler_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

配置 struct 把构造期依赖集中传入，便于测试替换。

> [!warning] 常见误解与迁移边界
> 可复用字段名初始化；跨包 struct 应避免无字段名字面量。误解是 struct 只承载数据，实际上它也定义不变量边界。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**struct 与复合字面量不是孤立语法，而是 `ReconcilerConfig` 所在边界用来表达约束的工具。**

上一章：[[05-类型定义别名与显式转换]] · 下一章：[[07-struct-tag与JSON字段语义]]

延伸阅读：[Go 语言规范：Struct types](https://go.dev/ref/spec#Struct_types)
