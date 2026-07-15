---
title: "15 string、[]byte 与 rune"
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

# 15 string、[]byte 与 rune

## 语法

string 是不可变字节序列；[]byte 适合 I/O/哈希；rune 表示 Unicode 码点。

**说明性片段：**

```go
s := "网关"
b := []byte(s)
r := []rune(s)
```

## NGF 中的应用

位置：`ngf:internal/framework/helpers/helpers.go:CapitalizeString`

**原样源码：**

```go
return strings.ToUpper(s[:1]) + s[1:]
```

输入字符串 → 按首字节切片 → ToUpper → 拼回结果。

## 相关测试

`internal/framework/helpers/helpers_test.go`
