---
title: "44 context.Context 的传递和取消"
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

# 44 context.Context 的传递和取消

## 语法

Context 沿调用链传递截止、取消和请求级值；不要存进长期业务数据或用 nil 代替。

**说明性片段：**

```go
func Handle(ctx context.Context, req Request) error {
	return process(ctx, req)
}
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster`

**原样源码：**

```go
broadcasterCtx, broadcasterCancel := context.WithCancel(ctx)
```

上层 ctx → broadcaster 子 ctx → 每个 listener 再派生子 ctx → shutdown 级联解除阻塞。

## 相关测试

`internal/controller/nginx/agent/broadcast/broadcast_test.go`
