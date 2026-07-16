---
title: "Advanced Routing 当前 kind 环境与资源拓扑"
tags: [nginx-gateway-fabric, examples, advanced-routing, runtime-forensics]
status: complete
note_type: runtime-trace
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
  kubernetes_server: v1.31.0
  gateway_api: v1.5.1
  helm_chart: nginx-gateway-fabric-2.6.5
  ngf: v2.6.5
  nginx: v1.31.2
  redaction: no-secrets-recorded
aliases:
  - Advanced Routing 环境快照
---

# Advanced Routing 当前 kind 环境与资源拓扑

> [!abstract] 现场结论
> 当前 context `kind-ngf-demo` 中，`Gateway/default/cafe` 已被 NGF 2.6.5 接受并编程。NGF 为它动态创建了一套名为 `cafe-nginx` 的独立数据面；宿主机 `127.0.0.1:8080` 经 kind 端口映射和 NodePort `31437` 到达该数据面。Gateway 状态里的 `10.96.1.41` 是集群内 Service ClusterIP，不是宿主机入口。

## 1. 环境指纹

| 层级 | 观察值 | 证据类型 |
|---|---|---|
| kubectl context | `kind-ngf-demo` | **运行观察** |
| Kubernetes Server | `v1.31.0` | **运行观察** |
| kubectl Client | `v1.29.9`，超过官方建议的 ±1 minor skew | **运行观察** |
| Gateway API CRD | `v1.5.1`，`standard` channel | **运行观察** |
| Helm Release | `ngf/nginx-gateway`，Chart/App `2.6.5` | **运行观察** |
| NGF 控制面镜像 | `ghcr.io/nginx/nginx-gateway-fabric:2.6.5` | **运行观察** |
| 数据面镜像 | `ghcr.io/nginx/nginx-gateway-fabric/nginx:2.6.5` | **运行观察** |
| NGINX | OSS `1.31.2` | **运行观察** |
| 当前源码 | `3a30b346...`，dirty=false | **源码事实** |
| 运行版本源码 | tag `v2.6.5` → `b6eb18e9...` | **源码事实** |

> [!warning] 版本差异
> 当前源码不是运行镜像对应的源码。涉及运行行为时，应优先对照 `git show v2.6.5:<path>`，再用 `nginx -T`、日志和请求结果确认；不能仅凭当前 HEAD 推断 2.6.5 的实际配置。

## 2. 示例目录声明了什么

| 文件 | 对象 | 责任 |
|---|---|---|
| `examples/advanced-routing/gateway.yaml` | `Gateway/cafe` | 声明 HTTP 80 listener |
| `cafe-routes.yaml` | `HTTPRoute/coffee`、`HTTPRoute/tea` | 声明 Header、Query、Method 和 PathPrefix 匹配 |
| `regex-route.yaml` | `HTTPRoute/coffee-regex` | 声明正则路径 `/coffee/[a-z]+` |
| `coffee.yaml` | 3 个 Deployment + 3 个 Service | 提供 coffee v1/v2/v3 后端 |
| `tea.yaml` | 2 个 Deployment + 2 个 Service | 提供 GET tea 和 POST tea 后端 |

文件指纹：

| 文件 | SHA-256 前 12 位 |
|---|---|
| `gateway.yaml` | `47ef0228de78` |
| `cafe-routes.yaml` | `ff07cc911dcb` |
| `regex-route.yaml` | `3864fab33edd` |
| `coffee.yaml` | `76d507d443a3` |
| `tea.yaml` | `fb91311c18e5` |

## 3. GatewayClass 与 NginxProxy 的配置谱系

| 阶段 | 字段/值 | 终端效果 |
|---|---|---|
| GatewayClass | `nginx`，controllerName=`gateway.nginx.org/nginx-gateway-controller` | 当前 NGF 接管使用此 class 的 Gateway |
| parametersRef | `NginxProxy/nginx-gateway/ngf-proxy-config` | 为 Gateway 选择数据面部署规格 |
| NginxProxy | Deployment、replicas=1、OSS image `2.6.5` | 每 Gateway 创建一个数据面 Deployment |
| NginxProxy Service | NodePort，listener 80 → `31437`，`externalTrafficPolicy: Local` | 暴露 Gateway listener |
| Gateway | `default/cafe`，listener `http:80` | 生成 `cafe-nginx` Service/Deployment 的 80 端口 |
| kind Docker 绑定 | host `8080` → node container `31437` | 宿主机通过 `127.0.0.1:8080` 访问 |

Gateway 只有 80 listener，因此 NginxProxy 虽然还预留了 listener 8443 → NodePort 30478，`cafe-nginx` Service 当前并未生成 8443 端口。宿主机 `8443` 映射对本例没有业务效果。

## 4. NGF 动态创建的数据面

`Gateway/default/cafe` 的 OwnerReference 链下实际存在：

| 资源 | 当前状态 | 作用 |
|---|---|---|
| `Deployment/default/cafe-nginx` | `1/1` Ready | 承载 NGINX 与 NGINX Agent |
| `Service/default/cafe-nginx` | NodePort，ClusterIP `10.96.1.41` | 把 listener 80 转到数据面 Pod |
| `ServiceAccount/default/cafe-nginx` | 存在 | 数据面身份及投射 Token |
| `ConfigMap/cafe-nginx-agent-config` | 存在 | Agent 的控制面地址、TLS、Token、标签和指标配置 |
| `ConfigMap/cafe-nginx-includes-bootstrap` | 存在 | 初始化 `main.conf` 与 `events.conf` |
| `Secret/cafe-nginx-agent-tls` | 存在，内容未读取 | Agent TLS 材料 |

Pod 内只有一个 Kubernetes container，但进程包括：

```text
PID 1   entrypoint.sh
PID 14  nginx master
PID 24  nginx-agent
PID 43+ nginx worker
```

这说明“NGINX 和 Agent 在同一容器”不等于“它们是同一个进程”。Agent 管理配置交付，NGINX 处理流量。

## 5. Gateway 与 Route 状态

| 对象 | 关键状态 |
|---|---|
| `GatewayClass/nginx` | `Accepted=True`、`SupportedVersion=True`、`ResolvedRefs=True` |
| `Gateway/default/cafe` | `Accepted=True`、`Programmed=True`，address=`10.96.1.41` |
| listener `http` | `Programmed=True`、`Accepted=True`、`ResolvedRefs=True`、attachedRoutes=3 |
| `HTTPRoute/coffee` | `Accepted=True`、`ResolvedRefs=True`，generation=2 |
| `HTTPRoute/tea` | `Accepted=True`、`ResolvedRefs=True`，generation=2 |
| `HTTPRoute/coffee-regex` | `Accepted=True`、`ResolvedRefs=True`，generation=1 |

Gateway 的 `allowedRoutes.namespaces.from` 由 API 默认成 `Same`。三条 Route 和 Gateway 都在 `default`，Backend Service 也在 `default`，因此本例不需要 `ReferenceGrant`。

## 6. Service 到 EndpointSlice 的实际解析

| Route backendRef | Service ClusterIP | NGINX 实际写入的 endpoint |
|---|---|---|
| `coffee-v1-svc:80` | `10.96.91.92` | `10.244.0.9:8080` |
| `coffee-v2-svc:80` | `10.96.192.210` | `10.244.0.10:8080` |
| `coffee-v3-svc:80` | `10.96.108.228` | `10.244.0.11:8080` |
| `tea-post-svc:80` | `10.96.191.212` | `10.244.0.12:8080` |
| `tea-svc:80` | `10.96.21.5` | `10.244.0.4:8080` |

> [!important] Service ClusterIP 不是 upstream 地址
> NGF 的 `ServiceResolver` 根据 Service 名和端口查询 EndpointSlice，只保留端口匹配、地址族允许且 `Ready=True` 的 endpoint。当前生成的 NGINX upstream 直接使用 Pod IP:8080，不经过业务 Service ClusterIP。

## 7. 现场中的额外资源与配置漂移

集群还有两组旧资源：

- `Service/coffee` → 旧 coffee Pod `10.244.0.3`；当前 advanced-routing 不引用它。
- `Service/tea` → 与 `tea-svc` 选中同一个 tea Pod；当前 Route 引用 `tea-svc`。

排障时应沿 `HTTPRoute.spec.rules[*].backendRefs` 查 Service，不能仅凭相似名字判断是否被使用。

Helm computed values 显示：

```yaml
nginxGateway:
  config:
    logging:
      level: info
```

但 live `NginxGateway/nginx-gateway/ngf-config` 已是 `logging.level: debug`、generation=2。==当前有效值是 live CR 的 debug，不是 Helm 安装时的 computed value。==

## 8. 关联笔记

- 上一篇：[[00-Advanced-Routing专题学习路线]]
- 下一篇：[[02-GatewayAPI到NGINX配置生成链路]]
- 请求行为：[[03-NGINX高级路由匹配机制]]
- 证据索引：[[99-Advanced-Routing源码索引与术语表]]
