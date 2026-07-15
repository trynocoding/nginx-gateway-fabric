---
title: "16 for range、整数 range 与迭代语义"
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

# 16 for range、整数 range 与迭代语义

> [!abstract] 本章唯一知识点
> range 根据操作数产生索引/值；Go 1.22 起可 range 整数。循环变量按迭代创建，仍需理解引用逃逸。

## 前置与完成标准

前置：[[15-string-byte与rune]]。学完应能解释“for range、整数 range 与迭代语义”，并在 NGF 中定位 `ServiceChangedPredicate.Update`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/predicate/service.go · ServiceChangedPredicate.Update（原样摘录）**

```go
for i := range len(oldSvc.Spec.Ports) {
```

- 定义：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`
- 精简链路：Service 更新事件 → 按整数 range 比较同位置端口 → 构建集合 → 决定是否过滤。
- 测试佐证：`internal/framework/controller/predicate/service_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

这里需要索引同时访问 old/new 两个等长切片，整数 range 比传统三段式更直接。

> [!warning] 常见误解与迁移边界
> 可在索引上界清晰时复用；两个切片长度必须先验证。误解是 range map 有稳定顺序。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**for range、整数 range 与迭代语义不是孤立语法，而是 `ServiceChangedPredicate.Update` 所在边界用来表达约束的工具。**

上一章：[[15-string-byte与rune]] · 下一章：[[17-多返回值与error-last]]

延伸阅读：[Go 语言规范：For statements](https://go.dev/ref/spec#For_statements)
