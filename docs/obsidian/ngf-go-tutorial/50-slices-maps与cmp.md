---
title: "50 slices、maps 与 cmp"
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

# 50 slices、maps 与 cmp

## 语法

现代标准库的 slices/maps 覆盖常见查找、排序、克隆和复制；go-cmp 用于测试结构差异。

**说明性片段：**

```go
copyOfMap := maps.Clone(original)
slices.Sort(values)
diff := cmp.Diff(want, got)
```

## NGF 中的应用

位置：`ngf:internal/controller/state/change_processor.go:ChangeProcessorImpl.mergedWAFBundles`

**原样源码：**

```go
maps.Copy(merged, graphBundles)
```

创建目标 map → Copy 图缓存 → Copy 较新轮询缓存覆盖同键 → 返回合并结果。

## 相关测试

`internal/controller/state/change_processor_test.go`
