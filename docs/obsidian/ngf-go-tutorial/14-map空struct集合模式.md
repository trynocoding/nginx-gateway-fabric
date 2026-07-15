---
title: "14 map[T]struct{} 集合模式"
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

# 14 map[T]struct{} 集合模式

> [!abstract] 本章唯一知识点
> 当只关心成员资格时，用 map[T]struct{} 表达集合；空 struct 不携带业务值。

## 前置与完成标准

前置：[[13-map-comma-ok与缺失值]]。学完应能解释“map[T]struct{} 集合模式”，并在 NGF 中定位 `ensureNoPortCollisions`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**cmd/gateway/validation.go · ensureNoPortCollisions（原样摘录）**

```go
seen := make(map[int]struct{})
```

- 定义：`ngf:cmd/gateway/validation.go:ensureNoPortCollisions`
- 精简链路：遍历端口 → seen 检测重复 → 重复时返回验证错误。
- 测试佐证：`cmd/gateway/validation_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

端口碰撞校验只需要成员关系，无需 bool 值。

> [!warning] 常见误解与迁移边界
> 可直接复用可比较键集合；需要顺序时另加切片或排序。误解是 map 保持插入顺序。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**map[T]struct{} 集合模式不是孤立语法，而是 `ensureNoPortCollisions` 所在边界用来表达约束的工具。**

上一章：[[13-map-comma-ok与缺失值]] · 下一章：[[15-string-byte与rune]]

延伸阅读：[Go 语言规范：Map types](https://go.dev/ref/spec#Map_types)
