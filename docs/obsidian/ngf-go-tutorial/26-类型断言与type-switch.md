---
title: "26 类型断言与 type switch"
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

# 26 类型断言与 type switch

## 语法

断言检查接口动态类型；comma-ok 避免 panic，type switch 适合多种互斥分支。

**说明性片段：**

```go
if s, ok := value.(string); ok { _ = s }

switch v := value.(type) {
case string:
	_ = v
case int:
	_ = v
}
```

## NGF 中的应用

位置：`ngf:internal/controller/handler.go:eventHandlerImpl.parseAndCaptureEvent`

**原样源码：**

```go
switch e := event.(type) {
```

EventLoop 交付 any → type switch 区分 Upsert/Delete/其他 → ChangeProcessor 捕获变更。

## 相关测试

`internal/controller/handler_test.go`
