---
title: "examples/external-authentication/cafe-routes.yaml 源码分析"
tags:
  - nginx-gateway-fabric
  - examples
  - source-analysis
status: complete
note_type: source-file-analysis
created: 2026-07-14
sources:
  - repo: nginx-gateway-fabric
    revision: 87e0580143fc
    dirty: false
source_file: examples/external-authentication/cafe-routes.yaml
source_sha256_12: 77d3cb0eb5bd
runtime_snapshots: []
---

# examples/external-authentication/cafe-routes.yaml 源码分析

> [!abstract] 核心结论
> 该文件声明 2 个对象（HTTPRoute）。它的核心价值不是展示 YAML 语法，而是提供一段可追踪输入：受管对象经过 Graph 验证与引用解析，普通工作负载则只通过 Service/Secret 等边界间接影响 NGF。

## 为什么选它

此文件属于二八抽样中的代表输入：它覆盖 **HTTPRoute** 的关键处理面，并能与同目录文件组成完整或近完整的因果链。重复的 Deployment/Service 变体、只改变名称的 Route 和操作型 README 不再逐篇展开。

## 文件现场与职责边界

| 文档 | API 版本 | Kind | Namespace | Name |
|---:|---|---|---|---|
| 1 | `gateway.networking.k8s.io/v1` | `HTTPRoute` | `default/继承 kubectl 上下文` | `coffee` |
| 2 | `gateway.networking.k8s.io/v1` | `HTTPRoute` | `default/继承 kubectl 上下文` | `tea` |

**源码事实**：文件指纹为 `77d3cb0eb5bd`，分析基于 revision `87e0580143fc`。本文没有把案例实际部署到集群，因此“生成了某条 NGINX 指令”属于源码可推导的预期，不是运行观察。

本文件中的对象处于 NGF 直接 watch、引用或配置生成边界内；其是否生效仍取决于完整引用链。

## 字段到行为的精确映射

| 对象 | 字段 | 案例值 | 进入系统后的含义 |
|---:|---|---|---|
| 1 | `metadata.name` | `coffee` | 组成 NamespacedName，是 Graph、引用解析与生成文件命名的稳定身份。 |
| 1 | `spec.parentRefs[0].name` | `gateway` | Route→listener 附着入口；group/kind/name/sectionName/namespace 决定候选父对象。 |
| 1 | `spec.parentRefs[0].sectionName` | `http` | Route→listener 附着入口；group/kind/name/sectionName/namespace 决定候选父对象。 |
| 1 | `spec.hostnames[0]` | `cafe.example.com` | 与 listener hostname 求交集，形成最终 virtual server/server_name。 |
| 1 | `spec.rules[0].matches[0].path` | `{...}` | 转为 path/method/header/query 或 gRPC service/method 匹配条件。 |
| 1 | `spec.rules[0].filters[0].type` | `ExternalAuth` | 按类型进入 header、CORS、redirect/rewrite、mirror 或 ExtensionRef 处理。 |
| 1 | `spec.rules[0].filters[0].externalAuth` | `{...}` | 按类型进入 header、CORS、redirect/rewrite、mirror 或 ExtensionRef 处理。 |
| 1 | `spec.rules[0].backendRefs[0].name` | `coffee` | 规则→backend 的数据谱系；name/port/weight 决定 upstream 身份、端口与流量比例。 |
| 1 | `spec.rules[0].backendRefs[0].port` | `80` | 规则→backend 的数据谱系；name/port/weight 决定 upstream 身份、端口与流量比例。 |
| 2 | `metadata.name` | `tea` | 组成 NamespacedName，是 Graph、引用解析与生成文件命名的稳定身份。 |
| 2 | `spec.parentRefs[0].name` | `gateway` | Route→listener 附着入口；group/kind/name/sectionName/namespace 决定候选父对象。 |
| 2 | `spec.parentRefs[0].sectionName` | `http` | Route→listener 附着入口；group/kind/name/sectionName/namespace 决定候选父对象。 |
| 2 | `spec.hostnames[0]` | `cafe.example.com` | 与 listener hostname 求交集，形成最终 virtual server/server_name。 |
| 2 | `spec.rules[0].matches[0].path` | `{...}` | 转为 path/method/header/query 或 gRPC service/method 匹配条件。 |
| 2 | `spec.rules[0].backendRefs[0].name` | `tea` | 规则→backend 的数据谱系；name/port/weight 决定 upstream 身份、端口与流量比例。 |
| 2 | `spec.rules[0].backendRefs[0].port` | `80` | 规则→backend 的数据谱系；name/port/weight 决定 upstream 身份、端口与流量比例。 |

> [!note] 阅读边界
> 表中“含义”描述字段进入控制器后的职责，不承诺所有字段都由 NGF 自己实现。例如 cert-manager 的 `Certificate` 最终产出 Secret，NGF 从 Secret 边界开始消费。

## 从案例到 NGINX 的源码链

```mermaid
flowchart LR
    A["kubectl/Helm 输入"] --> B["controller-runtime Watch"]
    B --> C["ChangeProcessor.Process"]
    C --> D["graph.BuildGraph"]
    D --> E["dataplane.BuildConfiguration"]
    E --> F["config.GeneratorImpl.Generate"]
    F --> G["Agent 文件下发与 NGINX reload"]
```

构造期由 `internal/controller/manager.go` 注册 Watch；运行期由
`internal/controller/handler.go:eventHandlerImpl.HandleEventBatch` 批处理事件。只有受管 Gateway 可达、引用有效的对象才会进入
`internal/controller/state/dataplane/configuration.go:BuildConfiguration`。最终
`internal/controller/nginx/config/generator.go:GeneratorImpl.Generate` 生成 HTTP/stream/include/证书等文件，再由
`internal/controller/nginx/agent/deployment.go:Deployment.SetFiles` 交给数据面。

本文件涉及的专用落点：

| Kind | Graph/生成入口 | 终端效果 | 测试佐证 |
|---|---|---|---|
| `HTTPRoute` | `internal/controller/state/graph/httproute.go:buildHTTPRoute,processHTTPRouteRules` | 把 parentRefs、hostname、match、filter、backendRefs 转成 L7Route，再进入 HTTP server/location/upstream | `internal/controller/state/graph/httproute_test.go` |

## 状态、失败与恢复

- 对象通过 API Server 校验，不代表它一定被当前 GatewayClass 管理；Graph 还会检查引用、作用域和支持能力。
- 引用的对象缺失、端口不匹配或跨 namespace 未获授权时，相关 Route/Policy 会带失败条件且不会产生预期配置。
- `parentRefs` 找不到 listener、hostname 无交集、Route kind 不被 allowedRoutes 接受时，不会形成有效 server/location。
- backend 无可用 EndpointSlice 时，路由结构可能存在，但请求侧会表现为无健康 upstream。

恢复路径是修正声明式对象后重新提交；controller-runtime 会产生新事件，`ChangeProcessorImpl.Process` 重建 Graph，并为受影响 Gateway 重新生成配置。NGF 的关键安全属性是：无效引用应留在状态条件中，而不是悄悄生成指向错误对象的配置。

## 如何验证这篇笔记

1. 静态校验：`kubectl apply --dry-run=server -f examples/external-authentication/cafe-routes.yaml`。
2. 状态校验：查看相关 Gateway/Route/Policy 的 `status.conditions`，不要只看对象是否存在。
3. 数据面校验：对照 `internal/controller/state/dataplane/configuration.go:BuildConfiguration` 与生成器测试；若有运行环境，再检查 agent 下发后的 `http.conf`/`stream.conf`。
4. 回归测试入口：`internal/controller/state/graph/httproute_test.go`。

## 二开提示

- 改 API 支持面时，通常要同步 Graph 验证、dataplane 中间表示、NGINX 生成器、状态条件和测试。
- 不要直接编辑生成文件或把示例中的外部控制器对象误归给 NGF。
- 修改 Route/filter/policy 时优先增加 Graph 负例，再增加生成器的精确字符串/结构断言。

## 最小心智模型

`示例文件` 只是期望状态；`Graph` 决定引用是否合法；`dataplane.Configuration` 决定哪些语义能进入生成器；NGINX 配置和资源状态才是可观察效果。中间任一门禁失败，都不能用“YAML 已创建”推断功能已生效。

## 关联笔记

- [[00-首页-学习路线]]
- [[99-源码索引与术语表]]
