---
title: "47 WaitGroup 与并发 fan-out/fan-in"
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

# 47 WaitGroup 与并发 fan-out/fan-in

> [!abstract] 本章唯一知识点
> WaitGroup 跟踪一组任务；Go 1.25 的 wg.Go 把 Add 与 goroutine 启动绑定，Wait 完成汇合。

## 前置与完成标准

前置：[[46-Mutex-RWMutex与临界区]]。学完应能解释“WaitGroup 与并发 fan-out/fan-in”，并在 NGF 中定位 `DeploymentBroadcaster.publisher`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/broadcast/broadcast.go · DeploymentBroadcaster.publisher（原样摘录）**

```go
			var wg sync.WaitGroup
			for _, channels := range currentListeners {
				wg.Go(func() {
```

- 定义：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster.publisher`
- 精简链路：复制订阅者 → 每个 listener 并发发送并等 ACK → wg.Wait → doneCh 通知 Send。
- 测试佐证：`internal/controller/nginx/agent/broadcast/broadcast_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

fan-out 降低多订阅者串行延迟，fan-in 保证一次发布完成语义。

> [!warning] 常见误解与迁移边界
> 可复用彼此独立的任务；每个任务仍要可取消。误解是 WaitGroup 传播错误，错误需另行设计。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**WaitGroup 与并发 fan-out/fan-in不是孤立语法，而是 `DeploymentBroadcaster.publisher` 所在边界用来表达约束的工具。**

上一章：[[46-Mutex-RWMutex与临界区]] · 下一章：[[48-atomic-race-detector与并发测试]]

延伸阅读：../ngf-agent-control-plane/22-DeploymentBroadcaster广播器机制与全链路.md
