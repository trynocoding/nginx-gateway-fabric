---
title: "07 struct tag 与 JSON 字段语义"
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

# 07 struct tag 与 JSON 字段语义

## 语法

tag 是字段元数据；json level/omitempty 同时决定字段名和空值省略，不改变 Go 字段本身。

**说明性片段：**

```go
type Config struct {
	Level string `json:"level,omitempty"`
}
```

## NGF 中的应用

位置：`ngf:apis/v1alpha1/nginxgateway_types.go:Logging.Level`

**原样源码：**

```go
Level *ControllerLogLevel `json:"level,omitempty"`
```

YAML/JSON level → API 解码到指针字段 → 默认与校验 → updateControlPlane。

## 相关测试

`internal/controller/config_updater_test.go`
