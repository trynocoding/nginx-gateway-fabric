---
title: "43 select 的多路复用语义"
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

# 43 select 的多路复用语义

## 语法

select 在可执行通信中选择一个；无可执行分支时阻塞，default 会改为非阻塞。

**说明性片段：**

```go
select {
case value := <-input:
	_ = value
case <-ctx.Done():
	return
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`

**原样源码：**

```go
	select {
	case <-ctx.Done():
```

Reconcile 构造事件 → 在取消和发送之间竞争 → 取消时不再阻塞工作队列。

## 相关测试

`internal/framework/controller/reconciler_test.go`
