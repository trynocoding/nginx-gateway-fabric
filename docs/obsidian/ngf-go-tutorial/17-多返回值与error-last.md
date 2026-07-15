---
title: "17 多返回值与 error-last 约定"
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

# 17 多返回值与 error-last 约定

> [!abstract] 本章唯一知识点
> 函数可返回多个结果；惯例把 error 放最后，让成功值和失败原因同时进入静态签名。

## 前置与完成标准

前置：[[16-for-range整数range与迭代]]。学完应能解释“多返回值与 error-last 约定”，并在 NGF 中定位 `parseS3URI`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/waf/fetch/s3/s3.go · parseS3URI（原样摘录）**

```go
func parseS3URI(uri string) (bucket, key string, err error) {
```

- 定义：`ngf:internal/framework/waf/fetch/s3/s3.go:parseS3URI`
- 精简链路：S3 URI → parseS3URI 返回 bucket/key/error → 调用者只在 err == nil 时构建请求。
- 测试佐证：`internal/framework/waf/fetch/s3/s3_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

命名结果说明语义，但正常路径仍应显式 return，避免隐藏状态。

> [!warning] 常见误解与迁移边界
> 可直接复用 error-last；不要用特殊零值替代错误。误解是多返回值等于 tuple 对象。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**多返回值与 error-last 约定不是孤立语法，而是 `parseS3URI` 所在边界用来表达约束的工具。**

上一章：[[16-for-range整数range与迭代]] · 下一章：[[18-可变参数]]

延伸阅读：[Effective Go: Multiple return values](https://go.dev/doc/effective_go#multiple-returns)
