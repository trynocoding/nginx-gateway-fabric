---
title: "30 any 与 comparable"
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

# 30 any 与 comparable

## 语法

any 接受任意类型；comparable 只接受可用 ==/!= 的类型，适合指针值比较或 map 键。

**说明性片段：**

```go
func Equal[T comparable](a, b T) bool { return a == b }

func Keep[T any](v T) T { return v }
```

## NGF 中的应用

位置：`ngf:internal/framework/helpers/helpers.go:EqualPointers`

**原样源码：**

```go
func EqualPointers[T comparable](p1, p2 *T) bool {
```

两个可选指针 → nil 归一 → 使用 == 比较 T 的零值或实际值。

## 相关测试

`internal/framework/helpers/helpers_test.go`
