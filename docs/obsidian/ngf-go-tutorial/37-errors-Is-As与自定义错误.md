---
title: "37 errors.Is、errors.As 与自定义错误类型"
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

# 37 errors.Is、errors.As 与自定义错误类型

> [!abstract] 本章唯一知识点
> Is 比较链中的哨兵语义；As 提取可赋值的具体错误类型。

## 前置与完成标准

前置：[[36-错误链与百分号w]]。学完应能解释“errors.Is、errors.As 与自定义错误类型”，并在 NGF 中定位 `ErrFailedAssert`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/status/updater.go · ErrFailedAssert（原样摘录）**

```go
var ErrFailedAssert = errors.New("type assertion failed")
```

- 定义：`ngf:internal/controller/status/updater.go:ErrFailedAssert`
- 精简链路：类型断言失败 → panic 包装 ErrFailedAssert；其他边界用 errors.Is/As 分类取消或状态错误。
- 测试佐证：`internal/controller/status/updater_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

调用者依赖错误类别而非消息文本，包装后仍能识别。

> [!warning] 常见误解与迁移边界
> 稳定错误类别可复用哨兵/自定义类型；不要比较 Error() 字符串。误解是 As 与类型断言只检查最外层。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**errors.Is、errors.As 与自定义错误类型不是孤立语法，而是 `ErrFailedAssert` 所在边界用来表达约束的工具。**

上一章：[[36-错误链与百分号w]] · 下一章：[[38-errors-Join多错误聚合]]

延伸阅读：[errors package](https://pkg.go.dev/errors)
