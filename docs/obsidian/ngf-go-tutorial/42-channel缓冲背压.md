---
title: "42 缓冲、无缓冲 channel 与背压"
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

# 42 缓冲、无缓冲 channel 与背压

## 语法

无缓冲发送要求接收者同步就绪；有限缓冲允许短暂解耦，但满后仍施加背压。

**说明性片段：**

```go
notify := make(chan struct{}, 1) // 最多缓存一个通知
work := make(chan Task)         // 无缓冲
```

## NGF 中的应用

位置：`ngf:internal/controller/status/queue.go:NewQueue`

**原样源码：**

```go
notifyCh: make(chan struct{}, 1),
```

状态入队 → 非阻塞尝试发送通知 → 单槽合并重复唤醒 → 消费者批量取队列。

## 相关测试

`internal/controller/status/queue_test.go`
