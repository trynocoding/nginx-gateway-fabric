---
title: "40 goroutine 的启动与退出责任"
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

# 40 goroutine 的启动与退出责任

> [!abstract] 本章唯一知识点
> 启动 goroutine 的代码必须定义停止信号、阻塞点解除方式和收尾责任。

## 前置与完成标准

前置：[[39-panic与不变量保护]]。学完应能解释“goroutine 的启动与退出责任”，并在 NGF 中定位 `NewDeploymentBroadcaster`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/broadcast/broadcast.go · NewDeploymentBroadcaster（原样摘录）**

```go
	go broadcaster.subscriber()
	go broadcaster.publisher()
```

- 定义：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster`
- 精简链路：构造器创建子 context → 启两个 goroutine → context 取消解除所有 select → 两循环返回。
- 测试佐证：`internal/controller/nginx/agent/broadcast/broadcast_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

生命周期由 broadcasterCtx 统一拥有，避免裸 goroutine 无法退出。

> [!warning] 常见误解与迁移边界
> 可复用 context 驱动生命周期；启动前先审查每个发送/接收是否可取消。误解是 goroutine 随调用函数返回自动结束。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**goroutine 的启动与退出责任不是孤立语法，而是 `NewDeploymentBroadcaster` 所在边界用来表达约束的工具。**

上一章：[[39-panic与不变量保护]] · 下一章：[[41-channel方向与所有权]]

延伸阅读：../ngf-agent-control-plane/22-DeploymentBroadcaster广播器机制与全链路.md
