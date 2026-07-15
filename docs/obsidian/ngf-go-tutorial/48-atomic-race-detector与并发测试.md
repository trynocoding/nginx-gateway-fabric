---
title: "48 atomic、race detector 与并发测试"
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

# 48 atomic、race detector 与并发测试

> [!abstract] 本章唯一知识点
> atomic 适合独立标量状态；复合不变量仍需锁。当前生产路径偏向 Mutex，测试用 atomic 计数并由 race detector 审核。

## 前置与完成标准

前置：[[47-WaitGroup与fan-out-fan-in]]。学完应能解释“atomic、race detector 与并发测试”，并在 NGF 中定位 `DeploymentBroadcaster.mu`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/grpc/filewatcher/filewatcher.go · FileWatcher.filesChanged（原样摘录）**

```go
	filesChanged *atomic.Bool
```

- 定义：`ngf:internal/controller/nginx/agent/grpc/filewatcher/filewatcher.go:FileWatcher.filesChanged`
- 精简链路：fsnotify 事件调用 Store(true) → ticker 周期 Load → 发送重连通知 → Store(false)；race 目标检查未同步访问。
- 测试佐证：`internal/controller/nginx/agent/grpc/filewatcher/filewatcher_test.go；Makefile`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

filesChanged 是独立布尔标志，atomic 避免事件与 ticker 并发访问产生数据竞争；需要同时维护多个字段的不变量时，NGF 仍使用 Mutex。

> [!warning] 常见误解与迁移边界
> 单计数器可考虑 atomic；先写出内存顺序和不变量再选。误解是 atomic 自动让整个算法无竞态。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**atomic、race detector 与并发测试不是孤立语法，而是 `FileWatcher.filesChanged` 所在边界用来表达约束的工具。**

上一章：[[47-WaitGroup与fan-out-fan-in]] · 下一章：[[49-EventLoop批处理与状态所有权]]

延伸阅读：[sync/atomic](https://pkg.go.dev/sync/atomic)
