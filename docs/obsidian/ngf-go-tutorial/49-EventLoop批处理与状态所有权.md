---
title: "49 EventLoop、批处理与状态所有权"
tags:
  - nginx-gateway-fabric
  - go-1-26
  - source-analysis
  - tutorial
status: complete
note_type: tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 49 EventLoop、批处理与状态所有权

> [!abstract] 本章唯一知识点
> 单一事件循环拥有批次切换；处理 goroutine 只读 currentBatch，新事件只写 nextBatch，形成双缓冲。

## 前置与完成标准

前置：[[48-atomic-race-detector与并发测试]]。学完应能解释“EventLoop、批处理与状态所有权”，并在 NGF 中定位 `EventLoop`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/events/loop.go · EventLoop（原样摘录）**

```go
	currentBatch EventBatch
	nextBatch    EventBatch
```

- 定义：`ngf:internal/framework/events/loop.go:EventLoop`
- 精简链路：eventCh → nextBatch → swapBatches → 单个 Handler goroutine → handlingDone → 下一批。
- 测试佐证：`internal/framework/events/loop_test.go；internal/controller/handler_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

所有批次切换由 Start goroutine 串行完成，从结构上降低共享状态竞争，并合并 NGINX reload。

> [!warning] 常见误解与迁移边界
> 可复用高成本重建的事件合并；必须接受批处理延迟并定义首批快照。误解是每个 Kubernetes 事件立即对应一次配置更新。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**EventLoop、批处理与状态所有权不是孤立语法，而是 `EventLoop` 所在边界用来表达约束的工具。**

上一章：[[48-atomic-race-detector与并发测试]] · 下一章：[[50-slices-maps与cmp]]

延伸阅读：../ngf-source-analysis/ngf-controller-runtime-interactions-obsidian.md
