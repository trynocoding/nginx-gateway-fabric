---
title: "46 Mutex、RWMutex 与临界区"
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

# 46 Mutex、RWMutex 与临界区

## 语法

Mutex 排他访问；RWMutex 允许并发读。锁保护的是不变量，临界区应短且避免未知阻塞调用。

**说明性片段：**

```go
var mu sync.RWMutex
mu.RLock()
value := state
mu.RUnlock()
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster.mu`

**原样源码：**

```go
mu sync.RWMutex
```

subscriber 写 listeners 持 Lock → publisher 快照时持 RLock → 复制后无锁等待网络响应。

## 相关测试

`internal/controller/nginx/agent/broadcast/broadcast_test.go`
