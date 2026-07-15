---
title: "14 map[T]struct{} 集合模式"
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

# 14 map[T]struct{} 集合模式

## 语法

当只关心成员资格时，用 map[T]struct{} 表达集合；空 struct 不携带业务值。

**说明性片段：**

```go
seen := make(map[string]struct{})
seen["gateway"] = struct{}{}
_, exists := seen["gateway"]
```

## NGF 中的应用

位置：`ngf:cmd/gateway/validation.go:ensureNoPortCollisions`

**原样源码：**

```go
seen := make(map[int]struct{})
```

遍历端口 → seen 检测重复 → 重复时返回验证错误。

## 相关测试

`cmd/gateway/validation_test.go`
