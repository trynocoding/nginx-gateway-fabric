---
title: "Advanced Routing 源码索引与术语表"
tags: [nginx-gateway-fabric, advanced-routing, source-index, glossary]
status: complete
note_type: source-index
created: 2026-07-16
updated: 2026-07-16
sources:
  - repo: nginx-gateway-fabric
    revision: 3a30b346cb20fe3589fd443878b82c3473f8a906
    dirty: false
  - repo: nginx-gateway-fabric
    revision: b6eb18e9b431657b872b84c626a8186587f43c41
    ref: v2.6.5
    dirty: false
runtime:
  context: kind-ngf-demo
  observed_at: 2026-07-16T16:47:41+08:00
  ngf: v2.6.5
  nginx: v1.31.2
---

# Advanced Routing 源码索引与术语表

## 1. 源码索引

> [!info] 版本使用方法
> 表中的符号在当前 HEAD 与 v2.6.5 中都核对过，但行号可能不同。解释运行中 2.6.5 时使用 `git show v2.6.5:<path>`；编辑当前代码时再打开工作区 HEAD。

| 主题/主张 | 证据类型 | 仓库与版本 | 路径与符号 | 责任/佐证 | 所属笔记 |
|---|---|---|---|---|---|
| Gateway/HTTPRoute/EndpointSlice Watch | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/manager.go:registerControllers` | controller-runtime 注册与 predicate | [[02-GatewayAPI到NGINX配置生成链路]] |
| EventBatch 入口 | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/handler.go:eventHandlerImpl.HandleEventBatch` | 捕获事件、Process、sendNginxConfig | [[02-GatewayAPI到NGINX配置生成链路]] |
| clusterState → Graph | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/state/change_processor.go:ChangeProcessorImpl.Process` | mutex、dirty gate、BuildGraph | [[02-GatewayAPI到NGINX配置生成链路]] |
| Gateway API 语义图 | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/state/graph/graph.go:BuildGraph` | 绑定、引用、验证、状态基础 | [[02-GatewayAPI到NGINX配置生成链路]] |
| Route/backendRef 验证 | **源码事实/测试佐证** | HEAD + v2.6.5 | `ngf:internal/controller/state/graph/httproute.go`、`backend_refs.go` | `httproute_test.go`、`backend_refs_test.go` | [[regex-route-yaml]] |
| 每 Gateway 创建数据面 | **源码事实/运行观察** | HEAD + v2.6.5 | `ngf:internal/controller/provisioner/provisioner.go:NginxProvisioner.RegisterGateway` | live `cafe-nginx` OwnerReference、创建日志 | [[01-当前kind环境与资源拓扑]] |
| Graph → Configuration | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/state/dataplane/configuration.go:BuildConfiguration` | 构建 server/upstream/policy IR | [[02-GatewayAPI到NGINX配置生成链路]] |
| Host/path 聚合 | **源码事实** | HEAD + v2.6.5 | `configuration.go:hostPathRules.upsertRoute,buildServers` | 把相同 host/path/type 的 match 聚合 | [[03-NGINX高级路由匹配机制]] |
| Match 优先级 | **源码事实/测试佐证** | HEAD + v2.6.5 | `ngf:internal/controller/state/dataplane/sort.go:sortMatchRules,higherPriority` | `sort_test.go`；matches.json 顺序 | [[03-NGINX高级路由匹配机制]] |
| Service → EndpointSlice | **源码事实/运行观察** | HEAD + v2.6.5 | `ngf:internal/controller/state/resolver/resolver.go:ServiceResolverImpl.Resolve` | live Pod IP:8080 与 upstream 一致 | [[01-当前kind环境与资源拓扑]] |
| location/internal match 生成 | **源码事实/运行观察** | HEAD + v2.6.5 | `ngf:internal/controller/nginx/config/servers.go:createLocations,createRouteMatch,createPath` | live http.conf + matches.json | [[03-NGINX高级路由匹配机制]] |
| 文件生成 | **源码事实** | HEAD + v2.6.5 | `ngf:internal/controller/nginx/config/generator.go:GeneratorImpl.Generate` | 生成 http/stream/include/secret 文件 | [[02-GatewayAPI到NGINX配置生成链路]] |
| 配置广播与 ACK | **源码事实/运行观察** | HEAD + v2.6.5 | `ngf:internal/controller/nginx/agent/agent.go:NginxUpdaterImpl.UpdateConfig` | `Config apply successful` 日志 | [[02-GatewayAPI到NGINX配置生成链路]] |
| NGINX 请求选择 | **运行观察** | NGF 2.6.5 | `/etc/nginx/conf.d/http.conf`、`matches.json` | 12 组请求矩阵 | [[04-kind验证与排障手册]] |

## 2. 运行产物索引

| 产物 | 观察值 | 用途 |
|---|---|---|
| Gateway address | `10.96.1.41` | `cafe-nginx` Service ClusterIP |
| 宿主机入口 | `127.0.0.1:8080` | kind Docker hostPort |
| NodePort | `31437` | listener 80 的节点端口 |
| 数据面 Pod | `cafe-nginx-6f76548f8c-fmp7l` | NGINX + Agent |
| `http.conf` SHA-256 | `9ce2740091ee...` | 观察时的 NGINX HTTP 配置指纹 |
| `matches.json` SHA-256 | `792b40c3ba75...` | 观察时的 njs 候选顺序指纹 |
| 控制面日志级别 | live `debug` | NginxGateway generation=2；与 Helm computed `info` 不同 |

## 3. 术语表

| 术语 | 含义 | 所属边界 |
|---|---|---|
| GatewayClass | 指定哪个控制器实现 Gateway，并可通过 parametersRef 引用实现配置 | Kubernetes / 控制面 |
| Gateway | listener 的期望状态；本例声明 HTTP 80 | Kubernetes / 控制面 |
| HTTPRoute | hostname、match、filter、backendRef 规则 | Kubernetes / 控制面 |
| NginxProxy | NGF CRD，决定每 Gateway 数据面 Deployment/Service 规格 | NGF Provisioner |
| Graph | 完成绑定、引用解析和验证后的 NGF 语义图 | NGF 控制面 |
| `dataplane.Configuration` | Graph 与 NGINX 文件生成器之间的中间表示，不等于已生效配置 | NGF 控制面 |
| Provisioner | 创建/修正每个 Gateway 的数据面 Kubernetes 对象 | NGF 控制面 |
| NGINX Agent | 与 NGF 建立控制连接、获取并应用配置、返回 ACK 的进程 | 数据面管理 |
| `server` | NGINX 中按 listen 和 Host/SNI 划分的虚拟服务器 | NGINX 数据面 |
| `location` | HTTP server 内的路径选择单元 | NGINX 数据面 |
| `upstream` | 一组可被 `proxy_pass` 引用的后端服务器 | NGINX 数据面 |
| njs | NGINX JavaScript；本例用于 Method/Header/Query 候选匹配 | NGINX 数据面 |
| internal redirect | NGINX 内部重新选择 location，不向客户端返回 3xx | NGINX 数据面 |
| PathPrefix | Gateway API 的路径段前缀；`/coffee` 不应匹配 `/coffeeabc` | Gateway API |
| EndpointSlice | Kubernetes Service 当前 endpoint 地址与端口的可扩展表示 | Kubernetes |
| Accepted | 控制器接受该对象或 attachment | Gateway API status |
| ResolvedRefs | 对象引用已被解析并获授权 | Gateway API status |
| Programmed | 控制器认为数据面已按当前 generation 编程 | Gateway API status |

## 4. 常用源码查询

**可运行查询示例：**

```bash
codegraph explore "HTTPRoute match 如何生成 matches.json 和 NGINX location"
codegraph explore "Gateway 如何触发 per-Gateway NGINX Deployment 与 Service"

git show v2.6.5:internal/controller/handler.go
git show v2.6.5:internal/controller/state/dataplane/sort.go
git show v2.6.5:internal/controller/nginx/config/servers.go

rg -n 'sortMatchRules|createRouteMatch|createPath' internal/controller
rg -n 'ServiceResolverImpl|resolveEndpoints' internal/controller/state/resolver
```

## 5. 未决项与下一步验证

| 未决项 | 置信度/影响 | 下一步 |
|---|---|---|
| 原始 kind 创建 YAML 保存位置未知 | 低影响；有效 Docker 绑定已观察 | 查部署脚本或 shell history，重建 `extraPortMappings` 来源 |
| 配置应用失败时旧配置的精确保留语义未做故障注入 | 不影响当前成功链；故障恢复结论保持克制 | 在隔离集群构造受控错误并观察 Agent ACK、文件与 NGINX master |
| 当前 HEAD 与 v2.6.5 存在功能差异 | 对开发 HEAD 有影响；对当前运行结论无影响 | 部署 HEAD 镜像后重跑 [[04-kind验证与排障手册]] |

## 6. 关联首页

回到 [[00-Advanced-Routing专题学习路线]]。
