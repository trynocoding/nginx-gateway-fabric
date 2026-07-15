---
title: "46 Mutex、RWMutex 与临界区"
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

# 46 Mutex、RWMutex 与临界区

> [!abstract] 本章唯一知识点
> Mutex 排他访问；RWMutex 允许并发读。锁保护的是不变量，临界区应短且避免未知阻塞调用。

## 前置与完成标准

前置：[[45-timeout-timer与ticker生命周期]]。学完应能解释“Mutex、RWMutex 与临界区”，并在 NGF 中定位 `DeploymentBroadcaster.mu`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/broadcast/broadcast.go · DeploymentBroadcaster.mu（原样摘录）**

```go
mu sync.RWMutex
```

- 定义：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster.mu`
- 精简链路：subscriber 写 listeners 持 Lock → publisher 快照时持 RLock → 复制后无锁等待网络响应。
- 测试佐证：`internal/controller/nginx/agent/broadcast/broadcast_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

先复制 listeners 再 fan-out，避免持锁跨 channel 阻塞。

> [!warning] 常见误解与迁移边界
> 可复用锁内快照、锁外慢操作；含锁 struct 不可复制。误解是 RWMutex 总比 Mutex 快。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Mutex、RWMutex 与临界区不是孤立语法，而是 `DeploymentBroadcaster.mu` 所在边界用来表达约束的工具。**

上一章：[[45-timeout-timer与ticker生命周期]] · 下一章：[[47-WaitGroup与fan-out-fan-in]]

延伸阅读：../ngf-agent-control-plane/22-DeploymentBroadcaster广播器机制与全链路.md
