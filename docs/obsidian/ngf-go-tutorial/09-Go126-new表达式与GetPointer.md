---
title: "09 Go 1.26 的 new(expr) 与项目 GetPointer 模式"
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

# 09 Go 1.26 的 new(expr) 与项目 GetPointer 模式

> [!abstract] 本章唯一知识点
> Go 1.26 允许 new(expr) 直接创建初值指针；当前 NGF 仍使用泛型 GetPointer，尚未迁移。

## 前置与完成标准

前置：[[08-指针nil与可选字段]]。学完应能解释“Go 1.26 的 new(expr) 与项目 GetPointer 模式”，并在 NGF 中定位 `GetPointer`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/helpers/helpers.go · GetPointer（原样摘录）**

```go
func GetPointer[T any](v T) *T {
	return &v
}
```

- 定义：`ngf:internal/framework/helpers/helpers.go:GetPointer`
- 精简链路：调用点传值 → GetPointer 返回逃逸安全的地址 → 可选 API/配置字段保存指针。
- 测试佐证：`internal/framework/helpers/helpers_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

GetPointer(v) 与 Go 1.26 的 new(v) 在此用途上等价；仓库现状仍以前者为准。

> [!warning] 常见误解与迁移边界
> 新代码可按团队兼容策略采用 new(expr)；批量替换要先确认最低 Go 版本。误解是返回局部变量地址会悬空，Go 会进行逃逸分析。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Go 1.26 的 new(expr) 与项目 GetPointer 模式不是孤立语法，而是 `GetPointer` 所在边界用来表达约束的工具。**

上一章：[[08-指针nil与可选字段]] · 下一章：[[10-数组与切片的类型差异]]

延伸阅读：[Go 1.26 Release Notes](https://go.dev/doc/go1.26)
