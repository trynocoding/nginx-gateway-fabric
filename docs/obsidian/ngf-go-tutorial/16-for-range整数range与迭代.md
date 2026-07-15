---
title: "16 for range、整数 range 与迭代语义"
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

# 16 for range、整数 range 与迭代语义

## 语法

range 根据操作数产生索引/值；Go 1.22 起可 range 整数。循环变量按迭代创建，仍需理解引用逃逸。

**说明性片段：**

```go
for i, v := range values {
	_ = i
	_ = v
}

for i := range 3 { _ = i }
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`

**原样源码：**

```go
for i := range len(oldSvc.Spec.Ports) {
```

Service 更新事件 → 按整数 range 比较同位置端口 → 构建集合 → 决定是否过滤。

## 相关测试

`internal/framework/controller/predicate/service_test.go`
