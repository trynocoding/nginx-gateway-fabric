---
title: "56 go generate、生成代码与人工代码边界"
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

# 56 go generate、生成代码与人工代码边界

> [!abstract] 本章唯一知识点
> go generate 只在显式执行时运行指令；生成物应由 schema/接口和生成命令负责，人工代码不直接改。

## 前置与完成标准

前置：[[55-logr结构化与上下文日志]]。学完应能解释“go generate、生成代码与人工代码边界”，并在 NGF 中定位 `go:generate counterfeiter`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/kubernetes/client.go · go:generate counterfeiter（原样摘录）**

```go
//go:generate go tool counterfeiter -generate
```

- 定义：`ngf:internal/framework/kubernetes/client.go:go:generate counterfeiter`
- 精简链路：Reader 接口旁声明生成指令 → counterfeiter 产出 fake → 测试配置调用结果。
- 测试佐证：`internal/framework/kubernetes/kubernetesfakes/fake_reader.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

指令靠近源接口，生成文件带 DO NOT EDIT；deepcopy 同理由 API schema 生成。

> [!warning] 常见误解与迁移边界
> 可复用可重复生成流程；升级生成器要检查 diff。误解是 go build 自动执行 go generate。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**go generate、生成代码与人工代码边界不是孤立语法，而是 `go:generate counterfeiter` 所在边界用来表达约束的工具。**

上一章：[[55-logr结构化与上下文日志]] · 下一章：[[57-表驱动子测试与并行测试]]

延伸阅读：[go generate](https://go.dev/blog/generate)
