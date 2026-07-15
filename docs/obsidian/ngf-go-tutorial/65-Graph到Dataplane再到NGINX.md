---
title: "65 Graph → Dataplane → NGINX 配置的分层转换"
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

# 65 Graph → Dataplane → NGINX 配置的分层转换

## 语法

Graph 表达 Kubernetes 语义；Dataplane.Configuration 表达 NGINX 所需中间模型；Generator 才负责文本文件。

**说明性片段：**

```go
graph := BuildGraph(clusterState)
config := BuildConfiguration(graph)
files := Generate(config)
UpdateConfig(files)
```

## NGF 中的应用

位置：`ngf:internal/controller/state/dataplane/configuration.go:BuildConfiguration`

**原样源码：**

```go
func BuildConfiguration(
```

Graph/Gateway → BuildConfiguration → dataplane.Configuration → config.Generator.Generate → NginxUpdater.UpdateConfig → Agent 应用文件。

## 相关测试

`internal/controller/state/dataplane/configuration_test.go；internal/controller/nginx/config/generator_test.go`
