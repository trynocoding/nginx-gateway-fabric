---
title: "11 append、容量与预分配"
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

# 11 append、容量与预分配

## 语法

append 在容量足够时复用底层数组，否则分配并复制；已知规模时预分配可减少增长。

**说明性片段：**

```go
items := make([]string, 0, 8)
items = append(items, "ngf")
```

## NGF 中的应用

位置：`ngf:internal/framework/events/loop.go:EventLoop.Start`

**原样源码：**

```go
el.nextBatch = append(el.nextBatch, e)
```

eventCh 收到事件 → append 到 nextBatch → 批次交换 → Handler 一次处理。

## 相关测试

`internal/framework/events/loop_test.go`
