---
title: NGF Pod 内 Delve 远程调试操作手册
date: 2026-07-14
tags:
  - nginx-gateway-fabric
  - kubernetes
  - kind
  - delve
  - debugging
aliases:
  - NGF Pod 调试
  - Delve Ephemeral Container 调试
status: verified
note_type: deployment-lab
source_revision: 1ed6f6786a617bccaa1b12b5da12fcb896cf8f9c
runtime_snapshots:
  - kind-kind Kubernetes context on 2026-07-14
  - Delve 1.27.0 linux-amd64
  - scripts/attach-dlv.sh verified with a Ready NGF Pod and 0.0.0.0 port-forward
---

# NGF Pod 内 Delve 远程调试操作手册

> [!success] 已验证范围
> 本文覆盖 Linux 宿主机上的 Debug 编译、kind 部署、控制面 Pod 定位、Delve 临时容器注入和
> `kubectl port-forward`。命令已在当前仓库和 kind 集群中验证，Delve 成功附加到
> `/usr/bin/gateway` 的 PID 1，并监听 `127.0.0.1:40000`。

> [!info] 本文边界
> 本文止于端口转发，不包含 Windows SSH 隧道和 GoLand 配置。相关控制面背景可参阅
> [[ngf-pod-startup-analysis-obsidian]] 和
> [[18-调试手册-日志-断点-常用命令]]。

## 两个已定位问题及根因

### Delve 镜像构建访问 `proxy.golang.org` 超时

失败发生在 `debug/Dockerfile` 的 builder 阶段：

```text
go install github.com/go-delve/delve/cmd/dlv@latest
Get "https://proxy.golang.org/...": i/o timeout
```

根因不是 NGF Go 代码编译失败，而是 ==Docker 构建容器无法访问默认 Go 模块代理==。宿主机执行
`go env -w GOPROXY=...` 并不能自动改变 Docker build 内部的 Go 环境；Makefile 必须显式传递
build argument，Dockerfile 也必须声明并使用它。

当前工作树已经形成完整传递链：

```text
make GOPROXY=...
  -> Makefile --build-arg GOPROXY=$(GOPROXY)
  -> debug/Dockerfile ARG GOPROXY
  -> GOPROXY="${GOPROXY}" go install ...
```

同时，Delve 已从不稳定的 `latest` 固定为 `v1.27.0`：

- `Makefile:33-34`：定义 `DLV_VERSION=v1.27.0`。
- `Makefile:58`：定义可覆盖的 `GOPROXY`。
- `Makefile:325-330`：把 `DLV_VERSION`、`GOPROXY` 传入 `docker build`。
- `debug/Dockerfile:6-11`：声明参数并用于 `go install`。

> [!warning] 版本前提
> 下文的 `make ... GOPROXY=...` 依赖上述 Makefile 和 Dockerfile 修改。旧版本如果没有
> `--build-arg GOPROXY=$(GOPROXY)`，仅在 make 命令行传入 `GOPROXY` 仍然无法修复容器内下载超时。

### PATCH 请求返回 `invalid character '\n' in string literal`

原命令把下面的 Delve shell 命令拆成了多行：

```text
... dlv attach $PID
--headless ... --only-same-
user=false
```

外层使用单引号保护 `--data` 时，Shell 会保留这些真实换行；但 JSON 字符串不能包含未转义的原始
换行，所以 Kubernetes API 在执行容器命令之前就拒绝了请求。

本文不再手写长 JSON 字符串，而是让 `jq` 生成 PATCH body。`jq --arg` 会正确转义 shell 命令，
从结构上避免复制或排版引入非法 JSON。

## Makefile 执行链

`debug-install-local-build` 是聚合目标，定义在 `Makefile:346-347`：

| Make 目标 | 作用 | 主要产物 |
| --- | --- | --- |
| `debug-build` | 使用 `-gcflags "all=-N -l"` 编译控制面 | `build/out/gateway` |
| `build-ngf-image` | 把 Debug 二进制装入控制面镜像 | `nginx-gateway-fabric:edge` |
| `build-nginx-image` | 构建 NGINX 数据面镜像 | `nginx-gateway-fabric/nginx:edge` |
| `debug-build-dlv-image` | 使用指定代理构建 Delve 镜像 | `dlv-debug:edge` |
| `debug-load-images` | 把本地镜像加载到 kind | kind/containerd 中的镜像 |
| `helm-install-local` | 安装 CRD 和 Helm release | `nginx-gateway` 命名空间资源 |

## 自动化方式（推荐）

仓库脚本 `scripts/attach-dlv.sh` 自动完成以下动作：

1. 检查 `kubectl`、`jq`、`curl` 以及当前 Kubernetes context/RBAC。
2. 用 label 自动寻找唯一的 Running 控制面 Pod；多个副本时拒绝猜测目标。
3. 校验目标容器、节点架构以及本地 Delve 镜像架构。
4. 检测并复用仍在运行的 `dlv` ephemeral container。
5. 必要时启动随机端口、仅监听回环地址的临时 `kubectl proxy`，完成 PATCH 后立即清理。
6. 等待 `dlv` 日志出现 `API server listening`。
7. 默认使用 `--continue`，避免 attach 后长期暂停 PID 1 导致 readiness 和 leader lease 失效。
8. 监听宿主机 `0.0.0.0:40000` 并转发到 Pod 的 Delve 端口。

> [!important] 调试部署必须关闭 leader election
> `--continue` 只能避免等待客户端连接期间暂停；真正命中断点后，整个 Go 进程仍会停止。如果 leader
> election 开启，超过 renew deadline 的断点会导致 `leader election lost`、NGF 主容器重启、`dlv`
> 被终止，GoLand 随即报告“调试器意外断开连接”。脚本默认检测并拒绝这种不安全配置。

已有 Helm release 执行：

```bash
helm upgrade nginx-gateway \
  ./charts/nginx-gateway-fabric \
  -n nginx-gateway \
  --reuse-values \
  --set nginxGateway.leaderElection.enable=false \
  --wait
```

首次构建安装时执行：

```bash
make GOARCH="$GOARCH" \
  GOPROXY=https://goproxy.cn,direct \
  HELM_PARAMETERS='--set nginxGateway.leaderElection.enable=false' \
  debug-install-local-build
```

在完成第 1～3 步的环境、集群和镜像准备后，直接运行：

```bash
./scripts/attach-dlv.sh
```

脚本会保持前台运行。远端客户端连接宿主机实际 IP：

```bash
dlv connect <宿主机IP>:40000
```

查看所有参数：

```bash
./scripts/attach-dlv.sh --help
```

常用方式：

```bash
# 只注入/验证，不启动端口转发
./scripts/attach-dlv.sh --no-port-forward

# 使用备用宿主机端口
./scripts/attach-dlv.sh --local-port 40001

# 显式指定 context 和 Pod
./scripts/attach-dlv.sh \
  --context kind-kind \
  --pod nginx-gateway-nginx-gateway-fabric-xxxxxxxxxx-xxxxx

# 保留旧的“attach 后立即暂停”行为
./scripts/attach-dlv.sh --pause-on-attach

# 明知 leader election 风险时强制 attach（不推荐）
./scripts/attach-dlv.sh --allow-leader-election

# 仅验证发现结果并输出 PATCH，不修改集群
./scripts/attach-dlv.sh --dry-run
```

> [!danger] `0.0.0.0` 暴露边界
> Delve 远程接口没有适合公网暴露的身份认证。脚本按当前调试需求默认监听 `0.0.0.0:40000`；必须使用
> 宿主机或网络防火墙把该端口限制到可信来源 IP，不得直接暴露到公网。

> [!warning] 已终止的临时容器
> Kubernetes 不允许删除、修改或复用 Pod 中已经存在的 ephemeral container。如果脚本检测到
> `dlv` 已终止，会停止并要求重建 Pod，不会自动执行破坏性删除。重建后再次运行脚本即可。

以下第 4～8 步保留为手工执行路径，用于理解或排查脚本内部动作。

## 1. 检查宿主机依赖

以下均为可执行命令：

```bash
cd /root/.workspace/middleware/nginx-k8s/nginx-gateway-fabric

go version
docker version
kind version
kubectl version --client
helm version
make --version
curl --version
jq --version
```

设置与宿主机一致的 Go 架构：

```bash
export GOARCH="$(go env GOARCH)"
printf 'GOARCH=%s\n' "$GOARCH"
```

常见值是 `amd64` 或 `arm64`。NGF 镜像、Delve 镜像与运行节点架构必须匹配。

## 2. 创建 kind 集群

先检查现有集群：

```bash
kind get clusters
```

如果当前集群可以删除并希望从干净环境开始：

```bash
make delete-kind-cluster
```

创建仓库配置的 kind 集群：

```bash
make create-kind-cluster
```

确认 kubectl 指向刚创建的集群：

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
```

> [!warning]
> 如果宿主机同时管理多个 Kubernetes 集群，继续操作前必须确认 current-context，避免把 Helm release
> 安装到错误集群。

## 3. 使用国内 Go 模块代理完成 Debug 构建与安装

执行：

```bash
make GOARCH="$GOARCH" \
    GOPROXY=https://goproxy.cn,direct \
    HELM_PARAMETERS='--set nginxGateway.leaderElection.enable=false' \
    debug-install-local-build
```

这个命令会完成 Debug 二进制、NGF 镜像、NGINX 镜像、Delve 镜像的构建，将镜像加载进 kind，
然后通过 Helm 安装 NGF。

验证代理确实传入 Docker build：

```bash
make -n GOARCH="$GOARCH" \
    GOPROXY=https://goproxy.cn,direct \
    debug-build-dlv-image |
  grep -- '--build-arg GOPROXY=https://goproxy.cn,direct'
```

验证本地 Delve 镜像：

```bash
docker image inspect dlv-debug:edge \
  --format 'id={{.Id}} architecture={{.Architecture}}'

docker run --rm dlv-debug:edge dlv version
```

预期 Delve 版本为：

```text
Version: 1.27.0
```

如果 Helm 提示 release 已存在：

```text
Error: cannot re-use a name that is still in use
```

删除旧 release 后重试：

```bash
helm uninstall nginx-gateway -n nginx-gateway

make GOARCH="$GOARCH" \
    GOPROXY=https://goproxy.cn,direct \
    HELM_PARAMETERS='--set nginxGateway.leaderElection.enable=false' \
    debug-install-local-build
```

## 4. 获取正确的控制面 Pod

等待 Deployment 就绪：

```bash
kubectl rollout status \
  deployment/nginx-gateway-nginx-gateway-fabric \
  -n nginx-gateway \
  --timeout=180s
```

查看 Pod 和 label：

```bash
kubectl get pods -n nginx-gateway --show-labels -o wide
```

当前 Helm chart 生成的 label 是
`app.kubernetes.io/name=nginx-gateway-fabric`，不是 `app.kubernetes.io/name=nginx-gateway`。

获取 Running 状态的控制面 Pod：

```bash
export POD_NAME="$(
  kubectl get pods \
    -n nginx-gateway \
    -l app.kubernetes.io/name=nginx-gateway-fabric \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
)"

printf 'POD_NAME=%s\n' "$POD_NAME"
```

验证 Pod 名不为空，且业务容器名为 `nginx-gateway`：

```bash
test -n "$POD_NAME"

kubectl get pod -n nginx-gateway "$POD_NAME" \
  -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

预期输出：

```text
nginx-gateway
```

## 5. 启动 Kubernetes API Proxy

在一个独立终端运行：

```bash
kubectl proxy --port=8001
```

预期：

```text
Starting to serve on 127.0.0.1:8001
```

保持该终端运行。可在另一个终端检查监听状态：

```bash
curl --fail --silent http://127.0.0.1:8001/version | jq .
```

## 6. 使用 `jq` 生成合法 PATCH 并注入 Delve

在另一个终端重新确认 `POD_NAME`：

```bash
printf 'POD_NAME=%s\n' "$POD_NAME"
test -n "$POD_NAME"
```

生成 PATCH body。`shellCommand` 必须保持为一个 shell 字符串；不要手工把它拆成多段 JSON 字符串：

```bash
PATCH_BODY="$(
  jq -n \
    --arg shellCommand 'PID=$(pgrep -o -f "^/usr/bin/gateway") && echo "attaching-to-pid=$PID" && exec dlv attach "$PID" --continue --headless --listen 127.0.0.1:40000 --api-version=2 --accept-multiclient --only-same-user=false' \
    '{
      spec: {
        ephemeralContainers: [
          {
            name: "dlv",
            command: ["/bin/sh", "-c", $shellCommand],
            image: "dlv-debug:edge",
            imagePullPolicy: "Never",
            targetContainerName: "nginx-gateway",
            stdin: true,
            tty: true,
            securityContext: {
              capabilities: {
                add: ["SYS_PTRACE"]
              },
              runAsNonRoot: false
            }
          }
        ]
      }
    }'
)"
```

发送前先验证 JSON：

```bash
printf '%s\n' "$PATCH_BODY" | jq -e . >/dev/null
```

执行 PATCH：

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --location \
  --request PATCH \
  "http://127.0.0.1:8001/api/v1/namespaces/nginx-gateway/pods/$POD_NAME/ephemeralcontainers" \
  --header 'Content-Type: application/strategic-merge-patch+json' \
  --data "$PATCH_BODY" |
  jq -r '.spec.ephemeralContainers[] | [.name, .targetContainerName] | @tsv'
```

预期输出：

```text
dlv    nginx-gateway
```

这里使用 `pgrep -o -f "^/usr/bin/gateway"`：

- `^` 限定命令行必须以 `/usr/bin/gateway` 开头，避免匹配包含该文本的注入 shell 自身。
- `-o` 在意外出现多个候选时只取最早启动的进程。
- `exec dlv` 让 Delve 直接替换临时容器中的 shell 进程。
- `--continue` 让 NGF 在 Delve attach 后继续运行，避免等待客户端期间 readiness 和 leader lease 失效。

## 7. 验证 Delve 已附加

查看临时容器状态：

```bash
kubectl get pod -n nginx-gateway "$POD_NAME" \
  -o jsonpath='{range .status.ephemeralContainerStatuses[*]}{.name}{"\t"}{.state}{"\n"}{end}'
```

查看 Delve 日志：

```bash
kubectl logs -n nginx-gateway "$POD_NAME" -c dlv --tail=40
```

预期：

```text
attaching-to-pid=1
API server listening at: 127.0.0.1:40000
```

确认成功后，可以在运行 `kubectl proxy` 的终端按 `Ctrl+C` 停止 proxy。后续端口转发不依赖
Kubernetes API Proxy 常驻。

> [!warning] 临时容器名称不可复用
> Ephemeral Container 添加后不能从现有 Pod 删除，也不能用同名配置覆盖。如果 `dlv` 已存在但已经退出，
> 应删除控制面 Pod，让 Deployment 创建新 Pod，然后重新获取 `POD_NAME` 并执行注入。

```bash
kubectl delete pod -n nginx-gateway "$POD_NAME"

kubectl rollout status \
  deployment/nginx-gateway-nginx-gateway-fabric \
  -n nginx-gateway \
  --timeout=180s
```

## 8. 转发 Delve 端口

在独立终端执行：

```bash
kubectl port-forward \
  --address=0.0.0.0 \
  -n nginx-gateway \
  "pod/$POD_NAME" \
  40000:40000
```

预期：

```text
Forwarding from 0.0.0.0:40000 -> 40000
```

保持该终端运行。此时 Delve 已经通过 Linux 宿主机的所有 IPv4 网卡暴露。远端执行
`dlv connect <宿主机IP>:40000`；同时必须配置防火墙来源限制。

## 常见失败对照

| 现象 | 根因 | 处理 |
| --- | --- | --- |
| `proxy.golang.org ... i/o timeout` | Docker builder 无法访问默认 Go proxy | 使用本文的 `GOPROXY=https://goproxy.cn,direct`，并确认 Makefile 传递 build arg |
| `invalid character '\n' in string literal` | JSON 字符串含未转义真实换行 | 使用 `jq -n --arg` 生成 PATCH body |
| `POD_NAME` 为空 | 使用了错误 label 或 Pod 尚未 Running | 使用 `app.kubernetes.io/name=nginx-gateway-fabric` 并检查 Pod 状态 |
| `ephemeralcontainers ... already exists` | 当前 Pod 已经添加过名为 `dlv` 的临时容器 | 重建控制面 Pod，再重新注入 |
| `could not attach ... operation not permitted` | 缺少 ptrace 权限或集群策略禁止该能力 | 检查 `SYS_PTRACE`、Pod Security 和节点 ptrace 策略 |
| `function not implemented` | 调试镜像与节点/目标二进制架构不一致 | 用正确的 `GOARCH` 重新构建和加载全部 Debug 镜像 |
| `connection refused` | Delve 未启动、已退出，或 port-forward 指向旧 Pod | 查看 `dlv` 日志，更新 `POD_NAME` 并重建转发 |
| GoLand“调试器意外断开连接”且 NGF 重启 | 断点暂停超过 leader lease renew deadline，主进程以 `leader election lost` 退出 | 设置 `nginxGateway.leaderElection.enable=false`，等待新 Pod 后重新运行脚本 |

## 验证记录与证据索引

本次运行验证：

```text
Kubernetes context: kind-kind
Control-plane label: app.kubernetes.io/name=nginx-gateway-fabric
Control-plane container: nginx-gateway
Control-plane image: nginx-gateway-fabric:edge
Delve image: dlv-debug:edge, linux/amd64
Delve version: 1.27.0
Attach result: attaching-to-pid=1
Listen result: API server listening at: 127.0.0.1:40000
Automated attach result: NGF remained 1/1 Running with Delve --continue
Remote port-forward result: 0.0.0.0:40000 -> Pod 40000
Long breakpoint result: paused for more than 20s, NGF restarts stayed 0 and Delve stayed Running
Continue result: NGF readiness recovered from 0/1 to 1/1
```

源码与配置证据：

- `Makefile:33-34`：Delve 固定版本。
- `Makefile:58`：Go 模块代理变量。
- `Makefile:320-347`：Debug 编译、镜像构建、加载和 Helm 安装目标。
- `debug/Dockerfile:4-15`：Delve builder、代理使用和最终镜像复制。
- `scripts/attach-dlv.sh`：Pod 发现、ephemeral container 注入/复用、验证和端口转发自动化。
- `docs/developer/debugging.md`：仓库原始 ephemeral container 调试流程。

> [!note] 工作树状态
> 本文对应源码 revision 为 `1ed6f6786a617bccaa1b12b5da12fcb896cf8f9c`；验证时
> `scripts/attach-dlv.sh` 尚未提交。因此在其他提交或干净 checkout 上操作前，应先确认该脚本以及
> Makefile/Dockerfile 的代理透传修正已经存在。
