---
title: "13 map、comma-ok 与缺失值语义"
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

# 13 map、comma-ok 与缺失值语义

## 语法

map 读取缺失键返回元素零值；comma-ok 额外区分缺失和存在但为零值。

**说明性片段：**

```go
value, ok := values[key]
if !ok {
	// key 不存在
}
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster.subscriber`

**原样源码：**

```go
if channels, exists := b.listeners[id]; exists {
```

取消订阅 ID → map comma-ok 查找 → cancel listener context → delete。

## 相关测试

`internal/controller/nginx/agent/broadcast/broadcast_test.go`
