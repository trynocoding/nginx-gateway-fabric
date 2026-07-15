---
title: "20 defer 与资源清理"
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

# 20 defer 与资源清理

> [!abstract] 本章唯一知识点
> defer 在外围函数返回前按后进先出执行，适合把清理紧邻资源获取。

## 前置与完成标准

前置：[[19-函数值闭包与高阶函数]]。学完应能解释“defer 与资源清理”，并在 NGF 中定位 `Fetcher.FetchBundle`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/waf/fetch/s3/s3.go · Fetcher.FetchBundle（原样摘录）**

```go
defer result.Body.Close()
```

- 定义：`ngf:internal/framework/waf/fetch/s3/s3.go:Fetcher.FetchBundle`
- 精简链路：S3 GetObject 成功 → 立即登记 Body.Close → ReadAll → 任一路径返回时清理。
- 测试佐证：`internal/framework/waf/fetch/s3/s3_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

资源获取成功后立刻 defer，减少错误分支遗漏。

> [!warning] 常见误解与迁移边界
> 可直接复用 Close/Unlock/cancel；大循环中 defer 会延迟到函数退出。误解是 defer 在当前代码块结束时执行。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**defer 与资源清理不是孤立语法，而是 `Fetcher.FetchBundle` 所在边界用来表达约束的工具。**

上一章：[[19-函数值闭包与高阶函数]] · 下一章：[[21-方法与接收者]]

延伸阅读：[Go 语言规范：Defer statements](https://go.dev/ref/spec#Defer_statements)
