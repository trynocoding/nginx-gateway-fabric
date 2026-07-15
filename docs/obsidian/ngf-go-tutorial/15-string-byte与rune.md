---
title: "15 string、[]byte 与 rune"
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

# 15 string、[]byte 与 rune

> [!abstract] 本章唯一知识点
> string 是不可变字节序列；[]byte 适合 I/O/哈希；rune 表示 Unicode 码点。

## 前置与完成标准

前置：[[14-map空struct集合模式]]。学完应能解释“string、[]byte 与 rune”，并在 NGF 中定位 `CapitalizeString`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/helpers/helpers.go · CapitalizeString（原样摘录）**

```go
return strings.ToUpper(s[:1]) + s[1:]
```

- 定义：`ngf:internal/framework/helpers/helpers.go:CapitalizeString`
- 精简链路：输入字符串 → 按首字节切片 → ToUpper → 拼回结果。
- 测试佐证：`internal/framework/helpers/helpers_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

当前实现适合项目中的 ASCII 标识；对任意 UTF-8 首字符应按 rune/utf8 边界处理。

> [!warning] 常见误解与迁移边界
> ASCII 约束明确时可复用；用户自然语言不应照搬。误解是 s[:1] 总取得一个字符。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**string、[]byte 与 rune不是孤立语法，而是 `CapitalizeString` 所在边界用来表达约束的工具。**

上一章：[[14-map空struct集合模式]] · 下一章：[[16-for-range整数range与迭代]]

延伸阅读：[Go Blog: Strings, bytes, runes and characters](https://go.dev/blog/strings)
