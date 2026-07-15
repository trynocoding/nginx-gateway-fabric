---
title: "49 EventLoop、批处理与状态所有权"
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

# 49 EventLoop、批处理与状态所有权

## 语法

单一事件循环拥有批次切换；处理 goroutine 只读 currentBatch，新事件只写 nextBatch，形成双缓冲。

**说明性片段：**

```go
current := []Event{}
next := []Event{}

next = append(next, event)
current, next = next, current[:0]
```

## NGF 中的应用

位置：`ngf:internal/framework/events/loop.go:EventLoop`

**原样源码：**

```go
	currentBatch EventBatch
	nextBatch    EventBatch
```

eventCh → nextBatch → swapBatches → 单个 Handler goroutine → handlingDone → 下一批。

## 相关测试

`internal/framework/events/loop_test.go；internal/controller/handler_test.go`
