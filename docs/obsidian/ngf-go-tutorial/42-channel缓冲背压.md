---
title: "42 缓冲、无缓冲 channel 与背压"
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

# 42 缓冲、无缓冲 channel 与背压

> [!abstract] 本章唯一知识点
> 无缓冲发送要求接收者同步就绪；有限缓冲允许短暂解耦，但满后仍施加背压。

## 前置与完成标准

前置：[[41-channel方向与所有权]]。学完应能解释“缓冲、无缓冲 channel 与背压”，并在 NGF 中定位 `NewQueue`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/status/queue.go · NewQueue（原样摘录）**

```go
notifyCh: make(chan struct{}, 1),
```

- 定义：`ngf:internal/controller/status/queue.go:NewQueue`
- 精简链路：状态入队 → 非阻塞尝试发送通知 → 单槽合并重复唤醒 → 消费者批量取队列。
- 测试佐证：`internal/controller/status/queue_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

缓冲 1 表达至少有工作而不是累计每次通知，避免生产者被重复信号阻塞。

> [!warning] 常见误解与迁移边界
> 可复用电平触发通知；不可用于必须逐条保存的数据。误解是增大缓冲能消除背压。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**缓冲、无缓冲 channel 与背压不是孤立语法，而是 `NewQueue` 所在边界用来表达约束的工具。**

上一章：[[41-channel方向与所有权]] · 下一章：[[43-select多路复用]]

延伸阅读：[Go 语言规范：Channel types](https://go.dev/ref/spec#Channel_types)
