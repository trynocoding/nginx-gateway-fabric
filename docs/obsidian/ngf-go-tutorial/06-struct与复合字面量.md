---
title: "06 struct 与复合字面量"
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

# 06 struct 与复合字面量

## 语法

struct 聚合有名字的字段；带字段名的复合字面量能抵抗字段顺序变化。

**说明性片段：**

```go
type Config struct {
	Name string
	Port int
}

cfg := Config{Name: "gateway", Port: 8080}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:ReconcilerConfig`

**原样源码：**

```go
type ReconcilerConfig struct {
```

Register 组装 ReconcilerConfig → NewReconciler 保存 cfg → Reconcile 读取依赖和策略。

## 相关测试

`internal/framework/controller/reconciler_test.go`
