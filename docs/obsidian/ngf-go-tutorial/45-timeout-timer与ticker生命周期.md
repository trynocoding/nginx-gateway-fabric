---
title: "45 timeout、timer 与 ticker 生命周期"
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

# 45 timeout、timer 与 ticker 生命周期

## 语法

timeout 限制一次操作；timer 触发一次；ticker 周期触发。创建者必须 cancel/Stop，避免资源滞留。

**说明性片段：**

```go
timer := time.NewTimer(time.Second)
defer timer.Stop()

ticker := time.NewTicker(time.Minute)
defer ticker.Stop()
```

## NGF 中的应用

位置：`ngf:internal/framework/waf/poller/poller.go:poller.run`

**原样源码：**

```go
	ticker := time.NewTicker(minInterval)
	defer ticker.Stop()
```

启动 poller → ticker 周期触发 fetch → ctx 取消或函数返回 → Stop。

## 相关测试

`internal/framework/waf/poller/poller_test.go`
