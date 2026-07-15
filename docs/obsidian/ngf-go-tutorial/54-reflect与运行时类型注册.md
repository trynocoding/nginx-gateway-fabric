---
title: "54 reflect 与运行时类型注册"
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

# 54 reflect 与运行时类型注册

## 语法

反射在运行期读取/创建类型；它绕过部分静态检查，失败路径必须被约束和测试。

**说明性片段：**

```go
t := reflect.TypeOf(value)
copy := reflect.New(t.Elem()).Interface()
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:Reconciler.mustCreateNewObject`

**原样源码：**

```go
obj, ok := reflect.New(t).Interface().(client.Object)
```

注册 ObjectType → TypeOf(...).Elem → reflect.New → 断言 client.Object → Reconcile 填充对象。

## 相关测试

`internal/framework/controller/reconciler_test.go`
