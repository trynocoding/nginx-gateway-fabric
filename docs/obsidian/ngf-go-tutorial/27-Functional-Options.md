---
title: "27 Functional Options"
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

# 27 Functional Options

> [!abstract] 本章唯一知识点
> Option 是修改私有配置的函数；构造入口先应用默认值，再按调用顺序覆盖。

## 前置与完成标准

前置：[[26-类型断言与type-switch]]。学完应能解释“Functional Options”，并在 NGF 中定位 `Option`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/register.go · Option（原样摘录）**

```go
type Option func(*config)
```

- 定义：`ngf:internal/framework/controller/register.go:Option`
- 精简链路：Register defaultConfig → 依次执行 options → 构造 builder/Reconciler。
- 测试佐证：`internal/framework/controller/register_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

可选项较多且持续演化时，调用点只表达需要覆盖的部分。

> [!warning] 常见误解与迁移边界
> 可复用到稳定构造 API；必填参数仍应显式。误解是 Options 自动验证冲突，验证仍需实现。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Functional Options不是孤立语法，而是 `Option` 所在边界用来表达约束的工具。**

上一章：[[26-类型断言与type-switch]] · 下一章：[[28-构造函数与不变量]]

延伸阅读：[Effective Go: Function values](https://go.dev/doc/effective_go#functions)
