---
title: "47 WaitGroup 与并发 fan-out/fan-in"
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

# 47 WaitGroup 与并发 fan-out/fan-in

## 语法

WaitGroup 跟踪一组任务；Go 1.25 的 wg.Go 把 Add 与 goroutine 启动绑定，Wait 完成汇合。

**说明性片段：**

```go
var wg sync.WaitGroup
wg.Go(func() { doWork() })
wg.Wait()
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/broadcast/broadcast.go:DeploymentBroadcaster.publisher`

**原样源码：**

```go
			var wg sync.WaitGroup
			for _, channels := range currentListeners {
				wg.Go(func() {
```

复制订阅者 → 每个 listener 并发发送并等 ACK → wg.Wait → doneCh 通知 Send。

## 相关测试

`internal/controller/nginx/agent/broadcast/broadcast_test.go`
