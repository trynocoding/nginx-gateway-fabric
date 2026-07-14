---
title: "examples/helm/experimental-nginx-plus/values.yaml Helm values 源码分析"
tags: [nginx-gateway-fabric, helm, examples, source-analysis]
status: complete
note_type: configuration-lineage
created: 2026-07-14
sources:
  - repo: nginx-gateway-fabric
    revision: 87e0580143fc
    dirty: false
source_file: examples/helm/experimental-nginx-plus/values.yaml
source_sha256_12: 526983fd14fc
---

# examples/helm/experimental-nginx-plus/values.yaml Helm values 源码分析

> [!abstract] 核心结论
> 这份 values 文件不是直接提交给 Kubernetes 的资源，而是 Helm 模板输入。关键配置分别流向控制面启动参数、RBAC 和 `NginxProxy`，因此必须检查渲染结果，不能从 values 文本直接推断运行状态。

## 为什么选它

该变体以很少的字段覆盖了高价值功能开关或产品形态，能够代表同目录中只改变组合关系的多个 Helm 示例。

## 精确配置谱系

| values 路径 | 值 | 模板与终端效果 |
|---|---|---|
| `nginxGateway.name` | `nginx-gateway` | 由 chart values schema 校验，再由对应模板渲染 |
| `nginxGateway.gwAPIExperimentalFeatures.enable` | `true` | `templates/deployment.yaml` 生成 `--gateway-api-experimental-features`，并扩展 RBAC |
| `nginx.plus` | `true` | `charts/nginx-gateway-fabric/templates/deployment.yaml` 生成 `--nginx-plus`；`nginxproxy.yaml` 选择 Plus 数据面参数 |
| `nginx.image.repository` | `private-registry.nginx.com/nginx-gateway-fabric/nginx-plus` | `charts/nginx-gateway-fabric/templates/nginxproxy.yaml` 写入 NginxProxy 的数据面镜像 |
| `nginx.imagePullSecret` | `nginx-plus-registry-secret` | `charts/nginx-gateway-fabric/templates/nginxproxy.yaml` 写入 NginxProxy 的数据面镜像 |

完整链路：

```text
examples values
  → charts/nginx-gateway-fabric/values.schema.json
  → templates/deployment.yaml / nginxproxy.yaml / _helpers.tpl
  → 控制面 flags + RBAC + GatewayClass/NginxProxy
  → manager 注册能力 + Provisioner 数据面形态
```

## 失败与边界

- `helm install` 成功只说明模板和 API 提交成功；实验 CRD、Plus 私有镜像凭据或 Snippets 功能仍可能在运行期失败。
- Plus 示例中的 `private-registry.nginx.com` 依赖本地镜像拉取 Secret；本文不记录也不要求任何真实凭据。
- Snippets 是高权限能力，chart 同时修改 flag 与 RBAC；只改其中一层会导致 watch 不注册或 API 访问被拒绝。

## 验证

```bash
helm template ngf charts/nginx-gateway-fabric -f examples/helm/experimental-nginx-plus/values.yaml
helm lint charts/nginx-gateway-fabric -f examples/helm/experimental-nginx-plus/values.yaml
```

重点检查渲染后的 Deployment 参数、ClusterRole 规则、GatewayClass.parametersRef 与 NginxProxy.spec。模板证据位于 `charts/nginx-gateway-fabric/templates/deployment.yaml`、`nginxproxy.yaml` 和 `_helpers.tpl`。

## 最小心智模型

`values` 决定安装时能力；Gateway/Route/Policy 决定运行时期望；二者交集才是 NGF 真正可处理的配置面。

## 关联笔记

- [[00-首页-学习路线]]
- [[99-源码索引与术语表]]
