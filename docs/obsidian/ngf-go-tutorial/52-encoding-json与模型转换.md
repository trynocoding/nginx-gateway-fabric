---
title: "52 encoding/json 与 API/领域模型转换"
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

# 52 encoding/json 与 API/领域模型转换

## 语法

JSON 是边界格式；Marshal/Unmarshal 受 tag、导出字段和自定义方法影响，不等于任意深拷贝。

**说明性片段：**

```go
type Config struct { Level string `json:"level"` }

b, err := json.Marshal(Config{Level: "info"})
```

## NGF 中的应用

位置：`ngf:internal/controller/config_updater.go:updateControlPlane`

**原样源码：**

```go
cfgBytes, err := json.Marshal(cfg.Spec)
```

用户 Spec marshal → 覆盖解码到带默认值的 controlConfig → 验证 → 应用日志级别。

## 相关测试

`internal/controller/config_updater_test.go`
