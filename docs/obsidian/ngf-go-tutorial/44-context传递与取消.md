---
title: "44 context.Context 的传递和取消"
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

# 44 context.Context 的传递和取消

> [!abstract] 本章唯一知识点
> Context 沿调用链传递截止、取消和请求级值；不要存进长期业务数据或用 nil 代替。

## 前置与完成标准

前置：[[43-select多路复用]]。学完应能解释“context.Context 的传递和取消”，并在 NGF 中定位 `NewDeploymentBroadcaster`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/broadcast/broadcast.go · NewDeploymentBroadcaster（原样摘录）**

```go
broadcasterCtx, broadcasterCancel := context.WithCancel(ctx)
```

- 定义：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster`
- 精简链路：上层 ctx → broadcaster 子 ctx → 每个 listener 再派生子 ctx → shutdown 级联解除阻塞。
- 测试佐证：`internal/controller/nginx/agent/broadcast/broadcast_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

父子取消树对应组件所有权树。

> [!warning] 常见误解与迁移边界
> 可直接复用首参数 ctx；创建 cancel 后由创建者负责调用。误解是取消会强制杀死 goroutine。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**context.Context 的传递和取消不是孤立语法，而是 `NewDeploymentBroadcaster` 所在边界用来表达约束的工具。**

上一章：[[43-select多路复用]] · 下一章：[[45-timeout-timer与ticker生命周期]]

延伸阅读：[Go Blog: Context](https://go.dev/blog/context)
