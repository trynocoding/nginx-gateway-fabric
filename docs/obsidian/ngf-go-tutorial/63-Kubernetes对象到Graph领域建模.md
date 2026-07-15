---
title: "63 Kubernetes 对象到 Graph 的领域建模"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 63 Kubernetes 对象到 Graph 的领域建模

## 语法

Graph 把原始对象、引用解析、有效性和附着关系收敛成领域模型，是验证与生成之间的防腐层。

**说明性片段：**

```go
type Graph struct {
	Gateways map[Key]*Gateway
	Routes   map[Key]*Route
	Services map[Key]*Service
}
```

## NGF 中的应用

位置：`ngf:internal/controller/state/graph/graph.go:BuildGraph`

**原样源码：**

```go
func BuildGraph(
```

ClusterState 快照 → BuildGraph 处理 GatewayClass/Gateway/Route/Policy/引用 → graph.Graph。

## 相关测试

`internal/controller/state/graph/graph_test.go`
