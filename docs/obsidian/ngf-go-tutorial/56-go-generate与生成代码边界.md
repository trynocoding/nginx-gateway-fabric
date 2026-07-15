---
title: "56 go generate、生成代码与人工代码边界"
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

# 56 go generate、生成代码与人工代码边界

## 语法

go generate 只在显式执行时运行指令；生成物应由 schema/接口和生成命令负责，人工代码不直接改。

**说明性片段：**

```go
//go:generate go tool counterfeiter -generate

// 运行：go generate ./...
```

## NGF 中的应用

位置：`ngf:internal/framework/kubernetes/client.go:go:generate counterfeiter`

**原样源码：**

```go
//go:generate go tool counterfeiter -generate
```

Reader 接口旁声明生成指令 → counterfeiter 产出 fake → 测试配置调用结果。

## 相关测试

`internal/framework/kubernetes/kubernetesfakes/fake_reader.go`
