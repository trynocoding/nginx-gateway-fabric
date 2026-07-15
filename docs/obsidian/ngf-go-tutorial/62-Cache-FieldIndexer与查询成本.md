---
title: "62 Cache、FieldIndexer 与查询成本"
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

# 62 Cache、FieldIndexer 与查询成本

## 语法

Cache 降低 API Server 读取；FieldIndexer 用预计算键换取按字段查询，索引函数必须确定且廉价。

**说明性片段：**

```go
func IndexByIP(obj client.Object) []string {
	return []string{obj.(*corev1.Pod).Status.PodIP}
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/index/pod.go:PodIPIndexFunc`

**原样源码：**

```go
func PodIPIndexFunc(obj client.Object) []string {
```

Manager 注册 status.podIP 索引 → Cache 更新 Pod 时计算键 → gRPC 连接按 IP 查询 Pod。

## 相关测试

`internal/framework/controller/index/pod_test.go`
