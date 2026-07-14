---
title: NGINX Gateway Fabric 最新发布版部署记录
date: 2026-06-24
tags:
  - kubernetes
  - nginx-gateway-fabric
  - helm
  - deployment
status: done
---

# NGINX Gateway Fabric 最新发布版部署记录

> [!info]
> 本文记录在当前 Kubernetes 集群中部署 NGINX Gateway Fabric 最新稳定发布版的实际步骤。当前官方最新稳定版为 `2.6.5`。

## 参考资料

- GitHub Releases: <https://github.com/nginx/nginx-gateway-fabric/releases>
- 官方 README 版本表: <https://github.com/nginx/nginx-gateway-fabric#nginx-gateway-fabric-releases>
- Helm Chart 文档: `charts/nginx-gateway-fabric/README.md`

## 本次环境

```text
项目路径：/root/.workspace/middleware/nginx-gateway-fabric
Kubernetes context：kubernetes-admin@kubernetes
Kubernetes server：https://apiserver.cluster.local:6443
Kubernetes version：v1.31.9
Helm version：v3.14.1
NGINX Gateway Fabric：2.6.5
Helm release：ngf
部署 namespace：nginx-gateway
```

## 1. 确认集群可用

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
```

本次集群节点：

```text
NAME   STATUS   ROLES           VERSION   INTERNAL-IP
cool   Ready    control-plane   v1.31.9   192.168.0.121
```

## 2. 确认最新稳定版本

本次通过两处官方来源确认最新稳定版：

- GitHub Releases 页面显示最新 release 为 `v2.6.5`。
- 官方 README 的 release 表显示 latest release 为 `2.6.5`。

如果需要在命令行确认 tag：

```bash
git ls-remote --tags https://github.com/nginx/nginx-gateway-fabric.git 'refs/tags/v*'
```

本次最新 tag：

```text
refs/tags/v2.6.5
```

## 3. 安装 Gateway API CRD

NGF 需要先安装它支持的 Gateway API CRD。本次使用 `v2.6.5` tag 中的 standard channel：

```bash
kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.6.5" \
  | kubectl apply -f -
```

本次创建的 Gateway API 资源包括：

```text
backendtlspolicies.gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
listenersets.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
tlsroutes.gateway.networking.k8s.io
```

## 4. 安装 NGINX Gateway Fabric

使用官方 OCI Helm chart 安装 `2.6.5` 稳定版：

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace \
  -n nginx-gateway \
  --wait \
  --version 2.6.5
```

本次 Helm 输出要点：

```text
Pulled: ghcr.io/nginx/charts/nginx-gateway-fabric:2.6.5
Digest: sha256:6a799f2a46f78db8790bd6e927ace8ee7699940654f3cee667ceeea465894ee9
STATUS: deployed
REVISION: 1
```

> [!note]
> 这里没有覆盖 Helm values，因此使用 chart 默认值。默认安装控制面，并创建默认 `GatewayClass/nginx`。如果要暴露实际业务流量，需要后续创建 `Gateway`、`HTTPRoute` 和后端服务；数据面资源会由控制面按 Gateway 动态创建。

## 5. 验证 Helm Release

```bash
helm status ngf -n nginx-gateway
helm list -n nginx-gateway
helm get values ngf -n nginx-gateway
```

本次结果：

```text
NAME: ngf
NAMESPACE: nginx-gateway
STATUS: deployed
CHART: nginx-gateway-fabric-2.6.5
APP VERSION: 2.6.5
USER-SUPPLIED VALUES: null
```

## 6. 验证控制面资源

```bash
kubectl -n nginx-gateway get pods,svc,deploy,cm,secret -o wide
```

本次关键结果：

```text
pod/ngf-nginx-gateway-fabric-647df8fcfd-pd92p       1/1   Running     0
pod/ngf-nginx-gateway-fabric-cert-generator-mzj2l   0/1   Completed   0

service/ngf-nginx-gateway-fabric   ClusterIP   10.96.0.78   <none>   443/TCP

deployment.apps/ngf-nginx-gateway-fabric   1/1   1   1
```

确认控制面镜像：

```bash
kubectl -n nginx-gateway get deploy ngf-nginx-gateway-fabric \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

输出：

```text
ghcr.io/nginx/nginx-gateway-fabric:2.6.5
```

## 7. 验证 GatewayClass

```bash
kubectl get gatewayclass -o wide
kubectl get gatewayclass nginx \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}:{.reason}{"\n"}{end}'
```

本次结果：

```text
NAME    CONTROLLER                                   ACCEPTED
nginx   gateway.nginx.org/nginx-gateway-controller   True

Accepted=True:Accepted
SupportedVersion=True:SupportedVersion
ResolvedRefs=True:ResolvedRefs
```

## 8. 验证 CRD

```bash
kubectl get crd | rg 'gateway.networking.k8s.io|gateway.nginx.org'
```

本次结果显示 Gateway API CRD 和 NGF 扩展 CRD 均已安装，包括：

```text
authenticationfilters.gateway.nginx.org
clientsettingspolicies.gateway.nginx.org
nginxgateways.gateway.nginx.org
nginxproxies.gateway.nginx.org
observabilitypolicies.gateway.nginx.org
proxysettingspolicies.gateway.nginx.org
ratelimitpolicies.gateway.nginx.org
snippetsfilters.gateway.nginx.org
snippetspolicies.gateway.nginx.org
upstreamsettingspolicies.gateway.nginx.org
wafpolicies.gateway.nginx.org
```

## 9. 当前部署状态

```text
NGF 最新稳定版 2.6.5 已通过 Helm 安装到 nginx-gateway namespace。
Helm release ngf 状态为 deployed。
控制面 Deployment/ngf-nginx-gateway-fabric 状态为 1/1 Available。
GatewayClass/nginx 已被控制器接受。
```

## 10. 部署 Cafe Demo

示例目录：`examples/cafe-example`

包含资源：

- `cafe.yaml`：创建 `coffee` / `tea` 两个后端 Deployment 和 Service。
- `gateway.yaml`：创建 `Gateway/default/gateway`，使用 `GatewayClass/nginx`。
- `cafe-routes.yaml`：创建 `HTTPRoute/default/coffee` 和 `HTTPRoute/default/tea`。

部署命令：

```bash
kubectl apply -f examples/cafe-example/cafe.yaml
kubectl apply -f examples/cafe-example/gateway.yaml
kubectl apply -f examples/cafe-example/cafe-routes.yaml
```

本次输出：

```text
deployment.apps/coffee created
service/coffee created
deployment.apps/tea created
service/tea created
gateway.gateway.networking.k8s.io/gateway created
httproute.gateway.networking.k8s.io/coffee created
httproute.gateway.networking.k8s.io/tea created
```

等待后端和数据面：

```bash
kubectl -n default rollout status deploy/coffee --timeout=180s
kubectl -n default rollout status deploy/tea --timeout=180s
kubectl -n default rollout status deploy/gateway-nginx --timeout=180s
```

### 10.1 当前环境 DNS 修正

> [!warning]
> 本次集群中 `kube-dns` Service IP `10.96.0.10:53` 从 Pod 内访问会超时，但直接访问 CoreDNS Pod IP 可正常解析。NGF 数据面 `gateway-nginx` 需要解析控制面 Service 地址 `ngf-nginx-gateway-fabric.nginx-gateway.svc`，因此默认数据面 Pod readiness 一开始失败。

确认现象：

```bash
kubectl -n default exec deploy/coffee -- nslookup kubernetes.default.svc.cluster.local 10.96.0.10
kubectl -n default exec deploy/coffee -- nslookup kubernetes.default.svc.cluster.local 100.123.94.66
```

本次结果：

```text
;; connection timed out; no servers could be reached

Server:		100.123.94.66
Address:	100.123.94.66:53
Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```

原因分析：

- `kube-dns` Service、EndpointSlice 和 kube-proxy IPVS 后端均存在，`10.96.0.10:53` 已配置到 CoreDNS Pod `100.123.94.66/67:53`。
- 直接访问 CoreDNS Pod IP 可以解析，说明 CoreDNS 进程本身正常。
- 从业务 Pod 中访问 `10.96.0.10:53` 时，节点抓包看到目的地址被改写为旧 Cilium 网段中的 `10.0.0.146:53`，而不是当前 CoreDNS Pod IP。
- 节点上同时残留了 Cilium 相关对象，包括 `cilium_host`、`cilium_net`、`cilium_vxlan`、`CILIUM_*` iptables 链、`/sys/fs/bpf/tc/globals/cilium_*` BPF map，以及挂在网卡上的 `cil_from_netdev` / `cil_to_host` tc BPF 程序。
- 当前集群实际使用 Calico，Pod IP 为 `100.123.94.x`。因此这不是 CoreDNS 配置问题，也不是 NGF 问题，而是节点上旧 Cilium datapath/BPF 状态残留，导致 kube-dns Service 流量被错误劫持或改写。

重启节点后，内存中的旧 Cilium BPF/tc 状态被清理，当前已可以通过 `kube-dns` Service IP `10.96.0.10` 正常解析域名。若再次复现，优先检查：

```bash
bpftool net
tc filter show dev enp0s2 ingress
ip link show | grep cilium
iptables-save | grep CILIUM
kubectl -n default exec deploy/coffee -- nslookup kubernetes.default.svc.cluster.local 10.96.0.10
```

用 `NginxProxy.spec.kubernetes.deployment.patches` 声明式修正数据面 DNS，让 NGF 生成的 `gateway-nginx` Deployment 直接使用可达的 CoreDNS Pod IP：

```bash
kubectl -n nginx-gateway patch nginxproxy ngf-proxy-config --type='merge' -p '{
  "spec": {
    "kubernetes": {
      "deployment": {
        "patches": [
          {
            "type": "StrategicMerge",
            "value": {
              "spec": {
                "template": {
                  "spec": {
                    "dnsPolicy": "None",
                    "dnsConfig": {
                      "nameservers": ["100.123.94.66", "100.123.94.67"],
                      "searches": [
                        "default.svc.cluster.local",
                        "svc.cluster.local",
                        "cluster.local"
                      ],
                      "options": [{"name": "ndots", "value": "5"}]
                    }
                  }
                }
              }
            }
          }
        ]
      }
    }
  }
}'
```

等待数据面重新收敛：

```bash
kubectl -n default rollout status deploy/gateway-nginx --timeout=180s
```

本次结果：

```text
deployment "gateway-nginx" successfully rolled out
```

确认数据面 DNS 配置：

```bash
kubectl -n default get deploy gateway-nginx \
  -o jsonpath='{.spec.template.spec.dnsPolicy}{"\n"}{.spec.template.spec.dnsConfig.nameservers}{"\n"}'
```

输出：

```text
None
["100.123.94.66","100.123.94.67"]
```

### 10.2 Demo 资源状态

```bash
kubectl -n default get pods,svc,endpoints,gateway,httproute -o wide
```

本次关键结果：

```text
pod/coffee-6db967495b-4ngck          1/1   Running
pod/gateway-nginx-5b54cb49fd-dsgf5   1/1   Running
pod/tea-7b7d6c947d-cg9l9             1/1   Running

service/gateway-nginx   LoadBalancer   10.96.1.40   <pending>   80:31201/TCP

endpoints/gateway-nginx   100.123.94.77:80

gateway.gateway.networking.k8s.io/gateway   nginx   PROGRAMMED=True
httproute.gateway.networking.k8s.io/coffee   ["cafe.example.com"]
httproute.gateway.networking.k8s.io/tea      ["cafe.example.com"]
```

Gateway / HTTPRoute 条件：

```bash
kubectl -n default get gateway gateway \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}:{.reason}{"\n"}{end}{range .status.listeners[*]}listener={.name} attachedRoutes={.attachedRoutes}{"\n"}{range .conditions[*]}{.type}={.status}:{.reason}{"\n"}{end}{end}'

kubectl -n default get httproute coffee tea \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.parents[*].conditions[*]}{.type}={.status}:{.reason}{"\n"}{end}{end}'
```

输出：

```text
Accepted=True:Accepted
Programmed=True:Programmed
listener=http attachedRoutes=2
Programmed=True:Programmed
Accepted=True:Accepted
ResolvedRefs=True:ResolvedRefs
Conflicted=False:NoConflicts

coffee
Accepted=True:Accepted
ResolvedRefs=True:ResolvedRefs
tea
Accepted=True:Accepted
ResolvedRefs=True:ResolvedRefs
```

### 10.3 访问测试

当前宿主机设置了 `http_proxy=http://127.0.0.1:10808`，测试 NodePort 时需要加 `--noproxy '*'`，避免请求走代理。

`gateway-nginx` Service 的 NodePort 为 `31201`，节点 IP 为 `192.168.0.121`。

测试 coffee：

```bash
curl --noproxy '*' \
  --resolve cafe.example.com:31201:192.168.0.121 \
  http://cafe.example.com:31201/coffee
```

本次结果：

```text
Server address: 100.123.94.74:8080
Server name: coffee-6db967495b-4ngck
Date: 24/Jun/2026:08:51:59 +0000
URI: /coffee
Request ID: 6d5514b190925912c40297abe450e684
```

测试 tea：

```bash
curl --noproxy '*' \
  --resolve cafe.example.com:31201:192.168.0.121 \
  http://cafe.example.com:31201/tea
```

本次结果：

```text
Server address: 100.123.94.75:8080
Server name: tea-7b7d6c947d-cg9l9
Date: 24/Jun/2026:08:51:59 +0000
URI: /tea
Request ID: 73c366d1a42d73fbb868384a560d515b
```

也可以不用 `--resolve`，直接访问 NodePort 并显式设置 Host：

```bash
curl --noproxy '*' \
  -H 'Host: cafe.example.com' \
  http://192.168.0.121:31201/coffee
```

本次结果：

```text
Server address: 100.123.94.74:8080
Server name: coffee-6db967495b-4ngck
Date: 24/Jun/2026:08:51:59 +0000
URI: /coffee
Request ID: daf7a124c7a2f4484ee1cf1e36254482
```

### 10.4 生成的 NGINX 配置片段

确认控制面已把 HTTPRoute 下发到数据面：

```bash
kubectl -n default exec deploy/gateway-nginx -- sh -c \
  'grep -R "coffee\\|tea\\|server_name\\|proxy_pass" -n /etc/nginx/conf.d /etc/nginx/main-includes /etc/nginx/events-includes | head -120'
```

本次结果：

```text
/etc/nginx/conf.d/http.conf:60:    server_name cafe.example.com;
/etc/nginx/conf.d/http.conf:63:    location /coffee/ {
/etc/nginx/conf.d/http.conf:81:        proxy_pass http://default_coffee_80;
/etc/nginx/conf.d/http.conf:86:    location = /coffee {
/etc/nginx/conf.d/http.conf:104:        proxy_pass http://default_coffee_80;
/etc/nginx/conf.d/http.conf:109:    location = /tea {
/etc/nginx/conf.d/http.conf:127:        proxy_pass http://default_tea_80;
/etc/nginx/conf.d/http.conf:161:upstream default_coffee_80 {
/etc/nginx/conf.d/http.conf:173:upstream default_tea_80 {
```

## 11. 清理命令

如果只需要清理 NGF release：

```bash
helm uninstall ngf -n nginx-gateway
```

如果也要清理 Gateway API CRD 和 NGF 扩展 CRD，需要额外删除对应 CRD。生产或共享集群中不要直接删除 CRD，避免误删已有 Gateway API 资源。

如果只清理 Cafe Demo：

```bash
kubectl delete -f examples/cafe-example/cafe-routes.yaml
kubectl delete -f examples/cafe-example/gateway.yaml
kubectl delete -f examples/cafe-example/cafe.yaml
```
