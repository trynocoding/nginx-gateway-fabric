---
title: "01 go.mod 中的语言版本与 toolchain"
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

# 01 go.mod 中的语言版本与 toolchain

> [!abstract] 本章唯一知识点
> go 指令规定模块可使用的语言语义；实际编译器由本机或 CI 选择，仓库没有单独的 toolchain 指令。

## 前置与完成标准

前置：[[00-首页-学习路线]]。学完应能解释“go.mod 中的语言版本与 toolchain”，并在 NGF 中定位 `go directive`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**go.mod · go directive（原样摘录）**

```text
go 1.26.0
```

- 定义：`ngf:go.mod:go directive`
- 精简链路：go 命令读取 go.mod → 采用 Go 1.26 语言规则 → 编译 cmd 与 internal 包。
- 测试佐证：`go.mod；tests/go.mod`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

版本指令是兼容性边界，不等于自动下载某个补丁版。当前环境实测 go1.26.0 linux/amd64。

> [!warning] 常见误解与迁移边界
> 可直接复用版本钉住方式；升级前必须跑生成、lint 与测试。不要把依赖模块的 go 指令误作主模块版本。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**go.mod 中的语言版本与 toolchain不是孤立语法，而是 `go directive` 所在边界用来表达约束的工具。**

上一章：[[00-首页-学习路线]] · 下一章：[[02-package导出规则与internal边界]]

延伸阅读：[Go 1.26 Release Notes](https://go.dev/doc/go1.26)
