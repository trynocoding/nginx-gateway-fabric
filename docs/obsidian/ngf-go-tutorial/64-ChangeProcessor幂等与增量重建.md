---
title: "64 ChangeProcessor、幂等与增量重建"
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

# 64 ChangeProcessor、幂等与增量重建

## 语法

ChangeProcessor 先累积 upsert/delete 到 ClusterState，再在批末决定是否重建完整 Graph；无语义变化返回 nil。

**说明性片段：**

```go
func (p *Processor) Process() *Graph {
	if !p.changed { return nil }
	return BuildGraph(p.state)
}
```

## NGF 中的应用

位置：`ngf:internal/controller/state/change_processor.go:ChangeProcessorImpl.Process`

**原样源码：**

```go
	if !c.getAndResetClusterStateChanged() {
		return nil
	}
```

事件批捕获变更 → changed predicate 去重 → Process 持锁 → 有变化 BuildGraph，无变化跳过。

## 相关测试

`internal/controller/state/change_processor_test.go`
