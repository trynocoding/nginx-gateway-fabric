---
title: "41 channel 方向与所有权表达"
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

# 41 channel 方向与所有权表达

> [!abstract] 本章唯一知识点
> <-chan T 只收、chan<- T 只发；方向写进 API 能限制误用并表达谁关闭 channel。

## 前置与完成标准

前置：[[40-goroutine启动与退出责任]]。学完应能解释“channel 方向与所有权表达”，并在 NGF 中定位 `Messenger`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/agent/grpc/messenger/messenger.go · Messenger（原样摘录）**

```go
Messages() <-chan *pb.DataPlaneResponse
```

- 定义：`ngf:internal/controller/nginx/agent/grpc/messenger/messenger.go:Messenger`
- 精简链路：handleRecv 拥有可写 outgoing → Messages 暴露只读视图 → 消费者无法发送或关闭。
- 测试佐证：`internal/controller/nginx/agent/grpc/messenger/messenger_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

生产者保留关闭权，消费者只观察数据。

> [!warning] 常见误解与迁移边界
> 可直接复用到组件边界；双向 channel 只留在所有者内部。误解是方向会创建新 channel。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**channel 方向与所有权表达不是孤立语法，而是 `Messenger` 所在边界用来表达约束的工具。**

上一章：[[40-goroutine启动与退出责任]] · 下一章：[[42-channel缓冲背压]]

延伸阅读：../ngf-agent-control-plane/08-订阅长流-Subscribe与配置下发.md
