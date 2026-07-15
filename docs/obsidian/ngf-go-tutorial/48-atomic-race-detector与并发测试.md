---
title: "48 atomic、race detector 与并发测试"
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

# 48 atomic、race detector 与并发测试

## 语法

atomic 对单个标量执行不可分割的并发读写；复合状态仍需要锁。race detector 用运行时检测发现未同步的内存访问。

**说明性片段：**

```go
var changed atomic.Bool
changed.Store(true)
if changed.Load() { changed.Store(false) }
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/grpc/filewatcher/filewatcher.go:FileWatcher.filesChanged`

**原样源码：**

```go
	filesChanged *atomic.Bool
```

文件事件调用 `Store(true)`；定时检查调用 `Load()`，发送通知后再 `Store(false)`。这个状态只有一个布尔值，适合使用 `atomic.Bool`。

## 相关测试

`internal/controller/nginx/agent/grpc/filewatcher/filewatcher_test.go；Makefile`
