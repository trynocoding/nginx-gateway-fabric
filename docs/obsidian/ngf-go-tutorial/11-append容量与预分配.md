---
title: "11 append、容量与预分配"
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

# 11 append、容量与预分配

> [!abstract] 本章唯一知识点
> append 在容量足够时复用底层数组，否则分配并复制；已知规模时预分配可减少增长。

## 前置与完成标准

前置：[[10-数组与切片的类型差异]]。学完应能解释“append、容量与预分配”，并在 NGF 中定位 `EventLoop.Start`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/events/loop.go · EventLoop.Start（原样摘录）**

```go
el.nextBatch = append(el.nextBatch, e)
```

- 定义：`ngf:internal/framework/events/loop.go:EventLoop.Start`
- 精简链路：eventCh 收到事件 → append 到 nextBatch → 批次交换 → Handler 一次处理。
- 测试佐证：`internal/framework/events/loop_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

EventLoop 用 append 表达动态批次；其他构建器会用 make(..., 0, n) 预估容量。

> [!warning] 常见误解与迁移边界
> 可直接复用 append；只有有可靠规模估计时预分配。误解是 append 一定原地修改。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**append、容量与预分配不是孤立语法，而是 `EventLoop.Start` 所在边界用来表达约束的工具。**

上一章：[[10-数组与切片的类型差异]] · 下一章：[[12-切片共享与防御性复制]]

延伸阅读：[Go 语言规范：Appending to slices](https://go.dev/ref/spec#Appending_and_copying_slices)
