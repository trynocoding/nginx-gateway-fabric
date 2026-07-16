---
title: "Advanced Routing kind 验证与排障手册"
tags: [nginx-gateway-fabric, advanced-routing, deployment-lab, debugging]
status: complete
note_type: deployment-lab
created: 2026-07-16
updated: 2026-07-16
sources:
  - repo: nginx-gateway-fabric
    revision: b6eb18e9b431657b872b84c626a8186587f43c41
    ref: v2.6.5
    dirty: false
runtime:
  context: kind-ngf-demo
  observed_at: 2026-07-16T16:47:41+08:00
  kubernetes_server: v1.31.0
  ngf: v2.6.5
  nginx: v1.31.2
  host_http_port: 8080
  node_port: 31437
  redaction: no-secrets-recorded
aliases:
  - Advanced Routing 实验手册
---

# Advanced Routing kind 验证与排障手册

## 1. 目标、边界与前提

> [!abstract] 实验结论
> 以下只读命令已在 `kind-ngf-demo`、NGF 2.6.5、NGINX 1.31.2 环境执行。它们验证宿主机入口、Gateway/Route 状态、Endpoint 解析、生成配置、Agent ACK 和最终后端。命令不会修改 Kubernetes 资源；最后的 HTTP 请求只会在 NGINX access log 中留下记录。

前提：

- 当前 context 是 `kind-ngf-demo`；
- `ngf-demo-control-plane` Docker 容器仍把 host 8080 映射到 container 31437；
- advanced-routing 资源仍在 `default` namespace；
- 后端镜像仍返回 `Server name` 文本，便于识别 Pod。

## 2. 先确认入口映射

**可运行示例（已验证）：**

```bash
kubectl config current-context
kubectl get nodes -o wide
docker inspect ngf-demo-control-plane \
  --format '{{json .HostConfig.PortBindings}}'
kubectl get svc cafe-nginx -n default -o wide
```

期望关系：

```text
host 127.0.0.1:8080
  -> Docker containerPort 31437
  -> Service cafe-nginx NodePort 31437
  -> Service port/targetPort 80
  -> cafe-nginx Pod port 80
```

不要直接把 `Gateway.status.addresses[0]=10.96.1.41` 当成宿主机访问地址；它是 ClusterIP。

## 3. 检查声明状态

**可运行示例（已验证）：**

```bash
kubectl get gatewayclass nginx -o wide
kubectl get gateway cafe -n default -o wide
kubectl get httproute coffee tea coffee-regex -n default -o wide
kubectl get deploy,svc,pod -n default -o wide
kubectl get endpointslice -n default -o wide
```

期望：

- GatewayClass `Accepted=True`；
- Gateway `Accepted=True`、`Programmed=True`；
- listener attachedRoutes=3；
- Route `Accepted=True`、`ResolvedRefs=True`；
- `cafe-nginx` 和五个后端 Pod Ready；
- 五个 backend Service 都有 Ready EndpointSlice。

> [!tip] 查实际引用，不猜名字
> 集群中存在旧 `coffee`、`tea` Service。排障时用 `kubectl get httproute ... -o yaml` 查看 `backendRefs`，当前真正使用的是带 `-svc` 的五个 Service。

## 4. 业务请求矩阵

**可运行示例（已验证）：**

```bash
curl -H 'Host: cafe.example.com' \
  http://127.0.0.1:8080/coffee

curl -H 'Host: cafe.example.com' \
  -H 'version: v2' \
  http://127.0.0.1:8080/coffee

curl -H 'Host: cafe.example.com' \
  'http://127.0.0.1:8080/coffee?TEST=v2'

curl -H 'Host: cafe.example.com' \
  -H 'headerRegex: header-a' \
  http://127.0.0.1:8080/coffee

curl -H 'Host: cafe.example.com' \
  'http://127.0.0.1:8080/coffee?queryRegex=query-z'

curl -X POST \
  -H 'Host: cafe.example.com' \
  http://127.0.0.1:8080/tea
```

观察响应中的 `Server name`：

| 用例 | 2026-07-16 实测状态 | 实测 Pod |
|---|---:|---|
| coffee default | 200 | `coffee-v1-b58596cd-5m98k` |
| `version:v2` | 200 | `coffee-v2-588dc87bf8-whgpg` |
| `TEST=v2` | 200 | `coffee-v2-588dc87bf8-whgpg` |
| regex Header | 200 | `coffee-v3-74c66666b6-98k8t` |
| regex Query | 200 | `coffee-v3-74c66666b6-98k8t` |
| 同时带 v2 与 regex Header | 200 | coffee-v2 |
| `/coffee/latte` + v2 Header | 200 | coffee-v1 |
| `/coffee/latte123` | 200 | coffee-v1 |
| `/coffeeabc` | 404 | 无后端 |
| GET `/tea` | 200 | `tea-7b7d6c947d-f7jbm` |
| POST `/tea` | 200 | `tea-post-8d4d8d66b-7lz98` |
| PUT `/tea` | 404 | 无后端 |
| 错误 Host | 404 | 无后端 |

## 5. 查看真正生效的 NGINX 配置

**可运行示例（已验证）：**

```bash
kubectl exec -n default deploy/cafe-nginx -c nginx -- nginx -T

kubectl exec -n default deploy/cafe-nginx -c nginx -- \
  sed -n '1,260p' /etc/nginx/conf.d/matches.json

kubectl exec -n default deploy/cafe-nginx -c nginx -- \
  sha256sum /etc/nginx/conf.d/http.conf /etc/nginx/conf.d/matches.json
```

重点搜索：

```text
server_name cafe.example.com
location ~ ^/coffee/[a-z]+
set $match_key 1_1
js_content httpmatches.redirect
/_ngf-internal-rule1-route0
upstream default_coffee-v2-svc_80
server 10.244.0.10:8080
```

当前哈希：

```text
http.conf     9ce2740091ee59440a93e355dfe9ca8f65d7ae4c2923f37ca7d98ad87dc63239
matches.json  792b40c3ba75edcc312b0dd6d48ae4a10c3cf74b2dc550fac3c9d0669c8a29dc
```

哈希只证明文件内容在观察时相同，不证明未来 reconcile 后仍保持不变。

## 6. 按顺序调试

| 检查点 | 最小命令 | 正常信号 | 异常时下一步 |
|---:|---|---|---|
| 1. context | `kubectl config current-context` | `kind-ngf-demo` | 切换到正确 context，避免查错集群 |
| 2. Host 入口 | `curl -v -H 'Host: cafe.example.com' 127.0.0.1:8080/coffee` | HTTP 200 | 查 Docker 8080→31437 映射 |
| 3. Gateway | `kubectl get gateway cafe -o yaml` | Accepted/Programmed=True | 查 GatewayClass 和 NginxProxy |
| 4. Route | `kubectl get httproute coffee -o yaml` | Accepted/ResolvedRefs=True | 查 parentRefs、hostnames、backendRefs |
| 5. Service | `kubectl get svc coffee-v2-svc -o yaml` | port 80→targetPort 8080 | 查 selector 是否匹配 Pod label |
| 6. EndpointSlice | `kubectl get endpointslice -l kubernetes.io/service-name=coffee-v2-svc -o yaml` | Ready Pod IP、port 8080 | 查 Pod readiness 与 Service selector |
| 7. 生成文件 | `kubectl exec deploy/cafe-nginx -- nginx -T` | 语法成功且有对应 location/upstream | 查 Controller Graph/Generator 日志 |
| 8. Agent ACK | 查数据面日志 `Config apply successful` | status OK | 查 gRPC、Token/TLS、配置错误 |
| 9. 后端 | 查看响应 `Server name` | 与请求矩阵相同 | 查 njs 顺序和正则 location 优先级 |

## 7. 常见症状对照

| 症状 | 最可能的层 | 本例中的解释 |
|---|---|---|
| 所有路径都 404 | Host/server | 缺少或写错 `Host: cafe.example.com` |
| `/coffeeabc` 404 | PathPrefix | 正确的路径段边界，不是故障 |
| PUT `/tea` 404 | njs Method | 只声明 GET 与 POST |
| `/coffee/latte` 不去 v2 | NGINX location | 正则路径 location 胜过 prefix+njs |
| 502/503 | upstream/endpoint | Service 后端不可连接或没有 Ready Endpoint |
| Route `ResolvedRefs=False` | Graph 引用验证 | backendRef 缺失、端口不匹配或越权 |
| 日志周期性 `context canceled` | Agent 连接生命周期 | 凭据刷新后重连；若随后 apply 成功则已恢复 |
| Helm 显示 info、日志却是 debug | live CR 漂移 | `NginxGateway/ngf-config` generation=2 已改为 debug |

## 8. 日志查询

**可运行示例（只读）：**

```bash
kubectl logs -n nginx-gateway deploy/ngf-nginx-gateway-fabric --since=6h | \
  rg 'resolved endpoints|Creating/Updating nginx resources|Sent nginx configuration|Successfully configured'

kubectl logs -n default deploy/cafe-nginx --since=6h | \
  rg 'Agent connected|config apply|Config apply successful'
```

若 `rg` 不在本机，可改用支持的日志工具；不要为了排障修改数据面容器里的生成文件，它们会被 Agent 管理并可能被下一次配置下发覆盖。

## 9. 清理边界

本次验证没有创建临时 Pod、没有 patch 资源、没有端口转发后台进程，因此无需清理。若以后删除 `Gateway/cafe`，其 OwnerReference 会使 NGF 管理的数据面对象被回收；后端 Deployment/Service 是用户资源，不属于该 OwnerReference 链。

## 10. 关联笔记

- 机制解释：[[03-NGINX高级路由匹配机制]]
- 资源现场：[[01-当前kind环境与资源拓扑]]
- 全链路：[[02-GatewayAPI到NGINX配置生成链路]]
- 索引：[[99-Advanced-Routing源码索引与术语表]]
