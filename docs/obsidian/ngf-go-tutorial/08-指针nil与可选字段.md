---
title: "08 指针、nil 与可选字段"
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

# 08 指针、nil 与可选字段

## 语法

指针让值具备缺失状态；解引用前必须证明非 nil，或先完成默认化。

**说明性片段：**

```go
var p *int // nil

v := 10
p = &v
```

## NGF 中的应用

位置：`ngf:internal/framework/helpers/helpers.go:EqualPointers`

**原样源码：**

```go
if p1 == nil && p2 == nil {
```

API 可选指针 → EqualPointers 归一 nil 与零值 → 比较是否发生语义变化。

## 相关测试

`internal/framework/helpers/helpers_test.go`
