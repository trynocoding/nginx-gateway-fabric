---
title: "53 text/template 与配置生成"
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

# 53 text/template 与配置生成

## 语法

模板把已验证的领域数据渲染成文本；模板执行不负责领域校验或 NGINX 语义正确性。

**说明性片段：**

```go
tmpl := template.Must(template.New("config").Parse(text))
err := tmpl.Execute(writer, data)
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/config/main_config.go:mainConfigTemplate`

**原样源码：**

```go
	mainConfigTemplate   = gotemplate.Must(gotemplate.New("main").Parse(mainConfigTemplateText))
```

dataplane 字段 → template fields → Execute → NGINX 配置文件 → updater 下发。

## 相关测试

`internal/controller/nginx/config/main_config_test.go`
