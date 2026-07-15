---
title: "09 Go 1.26 的 new(expr) 与项目 GetPointer 模式"
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

# 09 Go 1.26 的 new(expr) 与项目 GetPointer 模式

## 语法

`new(T)` 返回指向类型零值的指针；Go 1.26 新增 `new(expr)`，返回指向表达式结果的指针。

**说明性片段：**

```go
p1 := new(int)       // *p1 == 0
p2 := new(42)        // Go 1.26：*p2 == 42
```

## NGF 中的应用

位置：`ngf:internal/framework/helpers/helpers.go:GetPointer`

**原样源码：**

```go
func GetPointer[T any](v T) *T {
	return &v
}
```

调用点传值 → GetPointer 返回逃逸安全的地址 → 可选 API/配置字段保存指针。

## 相关测试

`internal/framework/helpers/helpers_test.go`
