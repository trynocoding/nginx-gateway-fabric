---
title: "41 channel 方向与所有权表达"
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

# 41 channel 方向与所有权表达

## 语法

<-chan T 只收、chan<- T 只发；方向写进 API 能限制误用并表达谁关闭 channel。

**说明性片段：**

```go
func consume(in <-chan Event) {}
func publish(out chan<- Event) {}
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/grpc/messenger/messenger.go:Messenger`

**原样源码：**

```go
Messages() <-chan *pb.DataPlaneResponse
```

handleRecv 拥有可写 outgoing → Messages 暴露只读视图 → 消费者无法发送或关闭。

## 相关测试

`internal/controller/nginx/agent/grpc/messenger/messenger_test.go`
