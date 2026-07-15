---
title: "27 Functional Options"
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

# 27 Functional Options

## 语法

Option 是修改私有配置的函数；构造入口先应用默认值，再按调用顺序覆盖。

**说明性片段：**

```go
type Option func(*Config)

func WithPort(port int) Option {
	return func(c *Config) { c.Port = port }
}
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/register.go:Option`

**原样源码：**

```go
type Option func(*config)
```

Register defaultConfig → 依次执行 options → 构造 builder/Reconciler。

## 相关测试

`internal/framework/controller/register_test.go`
