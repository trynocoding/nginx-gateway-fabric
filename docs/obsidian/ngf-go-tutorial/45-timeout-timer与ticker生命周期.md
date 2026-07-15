---
title: "45 timeout、timer 与 ticker 生命周期"
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

# 45 timeout、timer 与 ticker 生命周期

> [!abstract] 本章唯一知识点
> timeout 限制一次操作；timer 触发一次；ticker 周期触发。创建者必须 cancel/Stop，避免资源滞留。

## 前置与完成标准

前置：[[44-context传递与取消]]。学完应能解释“timeout、timer 与 ticker 生命周期”，并在 NGF 中定位 `poller.run`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/waf/poller/poller.go · poller.run（原样摘录）**

```go
	ticker := time.NewTicker(minInterval)
	defer ticker.Stop()
```

- 定义：`ngf:internal/framework/waf/poller/poller.go:poller.run`
- 精简链路：启动 poller → ticker 周期触发 fetch → ctx 取消或函数返回 → Stop。
- 测试佐证：`internal/framework/waf/poller/poller_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

ticker 生命周期被 run 词法作用域包住，停止责任明确。

> [!warning] 常见误解与迁移边界
> 可复用创建后立即 defer Stop/cancel；不要用 ticker 补偿执行耗时而不分析漂移。误解是停止 ticker 会关闭 C。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**timeout、timer 与 ticker 生命周期不是孤立语法，而是 `poller.run` 所在边界用来表达约束的工具。**

上一章：[[44-context传递与取消]] · 下一章：[[46-Mutex-RWMutex与临界区]]

延伸阅读：[time package](https://pkg.go.dev/time)
