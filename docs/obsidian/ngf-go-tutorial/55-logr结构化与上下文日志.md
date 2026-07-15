---
title: "55 logr 结构化日志和上下文日志"
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

# 55 logr 结构化日志和上下文日志

## 语法

结构化日志把消息与键值字段分离；上下文日志携带 reconcile 的资源身份和调用范围。

**说明性片段：**

```go
logger := logr.FromContextOrDiscard(ctx)
logger.Info("reconciled", "name", name)
```

## NGF 中的应用

位置：`ngf:internal/framework/events/loop.go:EventLoop.Start`

**原样源码：**

```go
batchLogger := el.logger.WithName("eventHandler").WithValues("batchID", el.currentBatchID)
```

EventLoop 分配 batchID → 派生 logger → Handler 全链共享批次上下文 → 日志可关联。

## 相关测试

`internal/framework/events/loop_test.go`
