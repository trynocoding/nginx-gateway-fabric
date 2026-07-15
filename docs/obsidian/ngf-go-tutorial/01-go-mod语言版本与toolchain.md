---
title: "01 go.mod 中的语言版本与 toolchain"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 01 go.mod 中的语言版本与 toolchain

## 语法

`go` 指令规定模块采用的语言版本；可选的 `toolchain` 指令指定建议使用的 Go 工具链版本。没有 `toolchain` 时，由本机或 CI 选择实际编译器。

**说明性片段：**

```go
module example.com/app

go 1.26.0

// toolchain go1.26.0 // 可选；NGF 没有设置
```

## NGF 中的应用

位置：`ngf:go.mod:go directive`

**原样源码：**

```text
go 1.26.0
```

go 命令读取 go.mod → 采用 Go 1.26 语言规则 → 编译 cmd 与 internal 包。

## 相关测试

`go.mod；tests/go.mod`
