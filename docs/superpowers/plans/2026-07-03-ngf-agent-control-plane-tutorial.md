# NGF Agent Control Plane Tutorial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Obsidian tutorial set that explains the NGINX Gateway Fabric control plane and NGINX Agent interaction flow from live Kubernetes resources to source code and secondary development.

**Architecture:** The tutorial is a map of focused Markdown notes under `nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/`. Each note has frontmatter, wikilinks, live-environment facts, source-code anchors, and a clear learning objective.

**Tech Stack:** Obsidian Flavored Markdown, Mermaid, Kubernetes/kubectl, Go source references, NGINX Gateway Fabric, NGINX Agent v3, gRPC MPI.

---

### Task 1: Create Tutorial Skeleton

**Files:**
- Create: `nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/00-首页-学习路线.md`
- Create: `nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/01-当前实验环境与资源拓扑.md`
- Create: `nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/02-NGF与Agent整体架构图.md`

- [ ] **Step 1: Create Obsidian index and environment notes**

Create notes with frontmatter, wikilinks, and current cluster facts from `kind-ngf-demo`.

- [ ] **Step 2: Verify headings and links**

Run:

```bash
rg -n '^#|\\[\\[' nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane
```

Expected: each file has one top-level title and wikilinks resolve to planned note names.

### Task 2: Explain Runtime Startup Paths

**Files:**
- Create: `03-NGF控制面启动流程.md`
- Create: `04-数据面Pod是如何被Provisioner创建的.md`
- Create: `05-Agent启动与插件总线机制.md`

- [ ] **Step 1: Bind startup notes to source**

Use NGF `internal/controller/manager.go` and Agent `cmd/agent/main.go`, `internal.App.Run`, MessagePipe and plugin concepts from existing docs.

- [ ] **Step 2: Verify source paths exist**

Run:

```bash
test -f nginx-gateway-fabric/internal/controller/manager.go
test -f agent/cmd/agent/main.go
```

Expected: exit code 0.

### Task 3: Explain gRPC and Main Interaction Flow

**Files:**
- Create: `06-gRPC-MPI协议与pb生成代码.md`
- Create: `07-连接建立-CreateConnection全链路.md`
- Create: `08-订阅长流-Subscribe与配置下发.md`
- Create: `09-文件拉取-FileService与配置文件交付.md`
- Create: `10-配置应用-ACK-状态回传.md`

- [ ] **Step 1: Document protocol roles**

Describe CommandService, FileService, CreateConnection, Subscribe, ManagementPlaneRequest, and DataPlaneResponse.

- [ ] **Step 2: Cross-check with CodeGraph**

Run:

```bash
codegraph explore "CreateConnection Subscribe FileService DeploymentStore" \
  --help >/dev/null 2>&1 || true
```

Expected: CodeGraph is available in the indexed repos; detailed exploration is performed from each project directory as needed.

### Task 4: Explain Gateway API to NGINX Config and Demo Trace

**Files:**
- Create: `11-GatewayAPI到NGINX配置生成链路.md`
- Create: `12-Cafe示例端到端溯源.md`

- [ ] **Step 1: Connect Kubernetes resources to generated data-plane state**

Use the live `Gateway`, `HTTPRoute`, `Service`, and `gateway-nginx` Deployment facts.

- [ ] **Step 2: Verify resource names**

Run:

```bash
kubectl get gateway,httproute,svc -A
```

Expected: `default/gateway`, `default/coffee`, `default/tea`, and `default/gateway-nginx` exist.

### Task 5: Explain Security, Identity, Development, and Debugging

**Files:**
- Create: `13-TLS-Token-鉴权与连接重置.md`
- Create: `14-ResourceID与数据面身份识别.md`
- Create: `15-二次开发指南-改协议.md`
- Create: `16-二次开发指南-改NGF控制面.md`
- Create: `17-二次开发指南-改Agent插件.md`
- Create: `18-调试手册-日志-断点-常用命令.md`
- Create: `19-设计原则总结.md`
- Create: `99-源码索引与术语表.md`

- [ ] **Step 1: Add secondary development guidance**

Document exact source areas, regeneration commands, and verification commands for common changes.

- [ ] **Step 2: Verify all planned notes exist**

Run:

```bash
for n in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 99; do
  ls nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/${n}-*.md
done
```

Expected: every command prints one file.

### Task 6: Final Verification

**Files:**
- Inspect all files under `nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane/`

- [ ] **Step 1: Check frontmatter, headings, and TODO placeholders**

Run:

```bash
rg -n '^(---|title:|tags:|status:|# )|TODO|TBD' nginx-gateway-fabric/docs/obsidian/ngf-agent-control-plane
```

Expected: frontmatter and headings are present; no `TODO` or `TBD` remains.

- [ ] **Step 2: Check git diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only tutorial and plan files are changed.
