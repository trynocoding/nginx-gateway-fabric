---
title: "64 ChangeProcessor、幂等与增量重建"
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

# 64 ChangeProcessor、幂等与增量重建

> [!abstract] 本章唯一知识点
> ChangeProcessor 先累积 upsert/delete 到 ClusterState，再在批末决定是否重建完整 Graph；无语义变化返回 nil。

## 前置与完成标准

前置：[[63-Kubernetes对象到Graph领域建模]]。学完应能解释“ChangeProcessor、幂等与增量重建”，并在 NGF 中定位 `ChangeProcessorImpl.Process`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/state/change_processor.go · ChangeProcessorImpl.Process（原样摘录）**

```go
	if !c.getAndResetClusterStateChanged() {
		return nil
	}
```

- 定义：`ngf:internal/controller/state/change_processor.go:ChangeProcessorImpl.Process`
- 精简链路：事件批捕获变更 → changed predicate 去重 → Process 持锁 → 有变化 BuildGraph，无变化跳过。
- 测试佐证：`internal/controller/state/change_processor_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

这是增量捕获 + 全量派生重建，幂等来自状态比较和确定性构建，不是局部修改 Graph。

> [!warning] 常见误解与迁移边界
> 可复用派生状态模式；重建成本必须可控且输出确定。误解是每个事件都直接 patch Graph。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**ChangeProcessor、幂等与增量重建不是孤立语法，而是 `ChangeProcessorImpl.Process` 所在边界用来表达约束的工具。**

上一章：[[63-Kubernetes对象到Graph领域建模]] · 下一章：[[65-Graph到Dataplane再到NGINX]]

延伸阅读：../ngf-agent-control-plane/21-Processor与EventHandler调用链分析.md
