---
title: "39 panic 作为程序员错误和不变量保护"
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

# 39 panic 作为程序员错误和不变量保护

## 语法

panic 适合不可恢复的程序员错误或已证明的不变量破坏，不应替代普通输入错误。

**说明性片段：**

```go
if impossibleState {
	panic("broken invariant")
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:Reconciler.mustCreateNewObject`

**原样源码：**

```go
panic("failed to create a new object")
```

注册时提供 ObjectType → reflect.New → 若不实现 client.Object 则 panic，暴露错误接线。

## 相关测试

`internal/framework/controller/reconciler_test.go`
