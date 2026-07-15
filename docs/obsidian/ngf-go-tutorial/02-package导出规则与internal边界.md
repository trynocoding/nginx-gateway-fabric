---
title: "02 package、导出规则与 internal 边界"
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

# 02 package、导出规则与 internal 边界

> [!abstract] 本章唯一知识点
> 包名组织命名空间，首字母大写控制导出；internal 由 Go 工具链限制跨父目录导入。

## 前置与完成标准

前置：[[01-go-mod语言版本与toolchain]]。学完应能解释“package、导出规则与 internal 边界”，并在 NGF 中定位 `package helpers`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/helpers/helpers.go · package helpers（原样摘录）**

```go
package helpers
```

- 定义：`ngf:internal/framework/helpers/helpers.go:package helpers`
- 精简链路：调用方导入 internal/framework/helpers → 只能访问 GetPointer 等导出名 → 编译器执行 internal 可见性检查。
- 测试佐证：`internal/framework/helpers/helpers_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

NGF 用 internal/framework 共享控制器基础设施，但仍防止其成为外部公共 API。

> [!warning] 常见误解与迁移边界
> 可复用小包和导出规则；只有仓库内部消费者才能复用 internal 代码。误解是小写名仅代表文档未公开，实际上编译器禁止跨包访问。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**package、导出规则与 internal 边界不是孤立语法，而是 `package helpers` 所在边界用来表达约束的工具。**

上一章：[[01-go-mod语言版本与toolchain]] · 下一章：[[03-变量声明与零值]]

延伸阅读：[Go 语言规范：Packages](https://go.dev/ref/spec#Packages)
