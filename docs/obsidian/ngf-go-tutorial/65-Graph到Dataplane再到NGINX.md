---
title: "65 Graph → Dataplane → NGINX 配置的分层转换"
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

# 65 Graph → Dataplane → NGINX 配置的分层转换

> [!abstract] 本章唯一知识点
> Graph 表达 Kubernetes 语义；Dataplane.Configuration 表达 NGINX 所需中间模型；Generator 才负责文本文件。

## 前置与完成标准

前置：[[64-ChangeProcessor幂等与增量重建]]。学完应能解释“Graph → Dataplane → NGINX 配置的分层转换”，并在 NGF 中定位 `BuildConfiguration`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/state/dataplane/configuration.go · BuildConfiguration（原样摘录）**

```go
func BuildConfiguration(
```

- 定义：`ngf:internal/controller/state/dataplane/configuration.go:BuildConfiguration`
- 精简链路：Graph/Gateway → BuildConfiguration → dataplane.Configuration → config.Generator.Generate → NginxUpdater.UpdateConfig → Agent 应用文件。
- 测试佐证：`internal/controller/state/dataplane/configuration_test.go；internal/controller/nginx/config/generator_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

分层让 API 验证、领域关系和文本渲染各有测试边界，也让 OSS/Plus 差异集中。

> [!warning] 常见误解与迁移边界
> 新增能力通常跨 API→Graph→Dataplane→Generator；不可直接在模板读取 Kubernetes 对象。误解是 Graph 本身就是 nginx.conf。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**Graph → Dataplane → NGINX 配置的分层转换不是孤立语法，而是 `BuildConfiguration` 所在边界用来表达约束的工具。**

上一章：[[64-ChangeProcessor幂等与增量重建]] · 下一章：[[99-源码索引与术语表]]

延伸阅读：../ngf-agent-control-plane/11-GatewayAPI到NGINX配置生成链路.md
