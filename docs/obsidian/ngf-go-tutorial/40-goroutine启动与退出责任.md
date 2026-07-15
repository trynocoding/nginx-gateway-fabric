---
title: "40 goroutine 的启动与退出责任"
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

# 40 goroutine 的启动与退出责任

## 语法

启动 goroutine 的代码必须定义停止信号、阻塞点解除方式和收尾责任。

**说明性片段：**

```go
go func() {
	select {
	case <-ctx.Done():
		return
	}
}()
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster`

**原样源码：**

```go
	go broadcaster.subscriber()
	go broadcaster.publisher()
```

构造器创建子 context → 启两个 goroutine → context 取消解除所有 select → 两循环返回。

## 相关测试

`internal/controller/nginx/agent/broadcast/broadcast_test.go`
