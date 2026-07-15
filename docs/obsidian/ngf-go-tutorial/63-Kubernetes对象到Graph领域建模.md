---
title: "63 Kubernetes 对象到 Graph 的领域建模"
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

# 63 Kubernetes 对象到 Graph 的领域建模

> [!abstract] 本章唯一知识点
> Graph 把原始对象、引用解析、有效性和附着关系收敛成领域模型，是验证与生成之间的防腐层。

## 前置与完成标准

前置：[[62-Cache-FieldIndexer与查询成本]]。学完应能解释“Kubernetes 对象到 Graph 的领域建模”，并在 NGF 中定位 `BuildGraph`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/state/graph/graph.go · BuildGraph（原样摘录）**

```go
func BuildGraph(
```

- 定义：`ngf:internal/controller/state/graph/graph.go:BuildGraph`
- 精简链路：ClusterState 快照 → BuildGraph 处理 GatewayClass/Gateway/Route/Policy/引用 → graph.Graph。
- 测试佐证：`internal/controller/state/graph/graph_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

生成器不直接遍历任意 Kubernetes 对象，状态计算和配置生成共享同一解释。

> [!warning] 常见误解与迁移边界
> 新增 API 语义应先进入 Graph；不要从模板旁路读取缓存对象。误解是 Graph 只是对象 map 的重命名。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Kubernetes 对象到 Graph 的领域建模不是孤立语法，而是 `BuildGraph` 所在边界用来表达约束的工具。**

上一章：[[62-Cache-FieldIndexer与查询成本]] · 下一章：[[64-ChangeProcessor幂等与增量重建]]

延伸阅读：../ngf-agent-control-plane/11-GatewayAPI到NGINX配置生成链路.md
