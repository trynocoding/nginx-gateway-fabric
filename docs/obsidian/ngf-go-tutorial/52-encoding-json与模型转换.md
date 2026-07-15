---
title: "52 encoding/json 与 API/领域模型转换"
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

# 52 encoding/json 与 API/领域模型转换

> [!abstract] 本章唯一知识点
> JSON 是边界格式；Marshal/Unmarshal 受 tag、导出字段和自定义方法影响，不等于任意深拷贝。

## 前置与完成标准

前置：[[51-io接口与资源所有权]]。学完应能解释“encoding/json 与 API/领域模型转换”，并在 NGF 中定位 `updateControlPlane`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/config_updater.go · updateControlPlane（原样摘录）**

```go
cfgBytes, err := json.Marshal(cfg.Spec)
```

- 定义：`ngf:internal/controller/config_updater.go:updateControlPlane`
- 精简链路：用户 Spec marshal → 覆盖解码到带默认值的 controlConfig → 验证 → 应用日志级别。
- 测试佐证：`internal/controller/config_updater_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

这里借 JSON 的缺失字段语义实现用户值覆盖默认值，适用于 API 结构映射。

> [!warning] 常见误解与迁移边界
> 仅在序列化语义正合适时复用；性能敏感深拷贝应使用显式转换或生成代码。误解是 omitempty 影响解码。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**encoding/json 与 API/领域模型转换不是孤立语法，而是 `updateControlPlane` 所在边界用来表达约束的工具。**

上一章：[[51-io接口与资源所有权]] · 下一章：[[53-text-template与配置生成]]

延伸阅读：[encoding/json](https://pkg.go.dev/encoding/json)
