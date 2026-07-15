---
title: "62 Cache、FieldIndexer 与查询成本"
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

# 62 Cache、FieldIndexer 与查询成本

> [!abstract] 本章唯一知识点
> Cache 降低 API Server 读取；FieldIndexer 用预计算键换取按字段查询，索引函数必须确定且廉价。

## 前置与完成标准

前置：[[61-Predicate与事件过滤]]。学完应能解释“Cache、FieldIndexer 与查询成本”，并在 NGF 中定位 `PodIPIndexFunc`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/framework/controller/index/pod.go · PodIPIndexFunc（原样摘录）**

```go
func PodIPIndexFunc(obj client.Object) []string {
```

- 定义：`ngf:internal/framework/controller/index/pod.go:PodIPIndexFunc`
- 精简链路：Manager 注册 status.podIP 索引 → Cache 更新 Pod 时计算键 → gRPC 连接按 IP 查询 Pod。
- 测试佐证：`internal/framework/controller/index/pod_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

索引避免每次鉴权列出全部 Pod；错误对象类型被视为注册不变量破坏。

> [!warning] 常见误解与迁移边界
> 可复用高频等值查询；索引增加内存和更新成本。误解是 FieldIndexer 会在 API Server 创建数据库索引。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Cache、FieldIndexer 与查询成本不是孤立语法，而是 `PodIPIndexFunc` 所在边界用来表达约束的工具。**

上一章：[[61-Predicate与事件过滤]] · 下一章：[[63-Kubernetes对象到Graph领域建模]]

延伸阅读：../ngf-agent-control-plane/20-PodIP字段索引与controller-runtime缓存机制.md
