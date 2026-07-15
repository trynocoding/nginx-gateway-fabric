---
title: "55 logr 结构化日志和上下文日志"
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

# 55 logr 结构化日志和上下文日志

> [!abstract] 本章唯一知识点
> 结构化日志把消息与键值字段分离；上下文日志携带 reconcile 的资源身份和调用范围。

## 前置与完成标准

前置：[[54-reflect与运行时类型注册]]。学完应能解释“logr 结构化日志和上下文日志”，并在 NGF 中定位 `EventLoop.Start`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/events/loop.go · EventLoop.Start（原样摘录）**

```go
batchLogger := el.logger.WithName("eventHandler").WithValues("batchID", el.currentBatchID)
```

- 定义：`ngf:internal/framework/events/loop.go:EventLoop.Start`
- 精简链路：EventLoop 分配 batchID → 派生 logger → Handler 全链共享批次上下文 → 日志可关联。
- 测试佐证：`internal/framework/events/loop_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

稳定字段名比字符串拼接更易查询；错误只在负责处理的边界记录。

> [!warning] 常见误解与迁移边界
> 可复用 WithName/WithValues；不要记录 Secret、token 或高基数字段。误解是 V(n) 代表严重级别。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**logr 结构化日志和上下文日志不是孤立语法，而是 `EventLoop.Start` 所在边界用来表达约束的工具。**

上一章：[[54-reflect与运行时类型注册]] · 下一章：[[56-go-generate与生成代码边界]]

延伸阅读：../ngf-source-analysis/ngf-logging-packages.md
