---
title: "50 slices、maps 与 cmp"
tags:
  - nginx-gateway-fabric
  - go-1-26
  - source-analysis
  - tutorial
status: complete
note_type: tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 50 slices、maps 与 cmp

> [!abstract] 本章唯一知识点
> 现代标准库的 slices/maps 覆盖常见查找、排序、克隆和复制；go-cmp 用于测试结构差异。

## 前置与完成标准

前置：[[49-EventLoop批处理与状态所有权]]。学完应能解释“slices、maps 与 cmp”，并在 NGF 中定位 `ChangeProcessorImpl.mergedWAFBundles`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/state/change_processor.go · ChangeProcessorImpl.mergedWAFBundles（原样摘录）**

```go
maps.Copy(merged, graphBundles)
```

- 定义：`ngf:internal/controller/state/change_processor.go:ChangeProcessorImpl.mergedWAFBundles`
- 精简链路：创建目标 map → Copy 图缓存 → Copy 较新轮询缓存覆盖同键 → 返回合并结果。
- 测试佐证：`internal/controller/state/change_processor_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

库函数直接表达覆盖顺序；helpers.Diff 则用 cmp.Diff 提供测试诊断。

> [!warning] 常见误解与迁移边界
> 可复用标准库算法；仍需说明覆盖、顺序和浅拷贝语义。误解是 maps.Clone/Copy 会深拷贝值。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**slices、maps 与 cmp不是孤立语法，而是 `ChangeProcessorImpl.mergedWAFBundles` 所在边界用来表达约束的工具。**

上一章：[[49-EventLoop批处理与状态所有权]] · 下一章：[[51-io接口与资源所有权]]

延伸阅读：[slices](https://pkg.go.dev/slices) · [maps](https://pkg.go.dev/maps)
