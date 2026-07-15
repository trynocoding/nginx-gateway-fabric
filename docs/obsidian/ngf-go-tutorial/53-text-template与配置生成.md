---
title: "53 text/template 与配置生成"
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

# 53 text/template 与配置生成

> [!abstract] 本章唯一知识点
> 模板把已验证的领域数据渲染成文本；模板执行不负责领域校验或 NGINX 语义正确性。

## 前置与完成标准

前置：[[52-encoding-json与模型转换]]。学完应能解释“text/template 与配置生成”，并在 NGF 中定位 `mainConfigTemplate`，说清调用效果与适用边界。本章只做源码导读，片段不承诺可独立运行。

## 最小模型

阅读时先判断类型、所有权和生命周期由谁规定，再读语法；这样能把记忆中的写法重新连回工程约束。

## NGF 生产代码证据

**internal/controller/nginx/config/main_config.go · mainConfigTemplate（原样摘录）**

```go
	mainConfigTemplate   = gotemplate.Must(gotemplate.New("main").Parse(mainConfigTemplateText))
```

- 定义：`ngf:internal/controller/nginx/config/main_config.go:mainConfigTemplate`
- 精简链路：dataplane 字段 → template fields → Execute → NGINX 配置文件 → updater 下发。
- 测试佐证：`internal/controller/nginx/config/main_config_test.go`
- 证据范围：源码事实固定于 `df175d68`；测试文件用于确认行为边界，不把框架推断写成项目事实。

## 工程取舍与边界

模板在初始化时 Must Parse，错误尽早暴露；输入由前置 Graph/Dataplane 层准备。

> [!warning] 常见误解与迁移边界
> 可复用稳定文本生成；不要把业务分支全部塞进模板。误解是 text/template 默认 HTML 转义。

复用判定：明确可复用的做法可直接采用；带条件的做法必须先满足相同输入、所有权与失败语义；指出不要或不可的部分不应照搬。

## 心智模型与下一步

一句话心智模型：**text/template 与配置生成不是孤立语法，而是 `mainConfigTemplate` 所在边界用来表达约束的工具。**

上一章：[[52-encoding-json与模型转换]] · 下一章：[[54-reflect与运行时类型注册]]

延伸阅读：../ngf-agent-control-plane/11-GatewayAPI到NGINX配置生成链路.md
