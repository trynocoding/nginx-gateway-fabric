---
title: "65 Graph 到 Dataplane 再到 NGINX"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: runtime-flow-tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 65 Graph 到 Dataplane 再到 NGINX

> [!abstract]
> NGF 的配置下发不是一次函数调用：事件批次先生成 Graph，Graph 再编译为 dataplane Configuration，模板生成带 hash 的文件元数据，Deployment 去重后广播给已连接的 NGINX Agent，Agent 按需拉取内容、应用并回报结果，最后错误进入 Gateway status。

## 学习目标与前置

- 从输入、纯转换、副作用和反馈四段追踪完整链路；
- 理解配置模型、文件元数据、内容传输为何分层；
- 掌握 hash 去重、广播事务、锁和错误聚合；
- 区分 NGINX OSS 全配置应用与 NGINX Plus upstream API 更新；
- 能定位“Graph 正确但 NGINX 未更新”的具体一跳。

前置：[[41-channel方向与所有权]]、[[49-EventLoop批处理与状态所有权]]、[[63-Kubernetes对象到Graph领域建模]]、[[64-ChangeProcessor幂等与增量重建]]。

## 1. 先建立编译流水线思维

```text
Kubernetes events
  -> ClusterState / Graph
  -> dataplane.Configuration
  -> []agent.File{Meta, Contents}
  -> ConfigApplyRequest(file overviews)
  -> Agent GetFile/GetFileStream
  -> Agent applies NGINX config
  -> response / pod error
  -> Gateway status
```

Graph 负责引用与有效性，Configuration 负责数据面语义，Generator 负责模板与文件，Agent transport 负责传输和应答，Status 负责反馈。每层都不越权，才能独立测试和定位错误。

## 2. 完整可运行 Demo：生成、去重、应用、反馈

生成阶段应接近纯函数；`sha256.Sum256` 生成的 hash 用于内容寻址和去重，不是加密。Go 的 map 遍历顺序不稳定，所以哈希前先排序。

```go
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"
)

type Graph struct{ Routes map[string]string }
type Configuration struct{ Lines []string }

type File struct {
	Name, Hash string
	Contents   []byte
}

func BuildConfiguration(g Graph) Configuration {
	names := make([]string, 0, len(g.Routes))
	for name := range g.Routes {
		names = append(names, name)
	}
	sort.Strings(names)
	lines := make([]string, 0, len(names))
	for _, name := range names {
		lines = append(lines, fmt.Sprintf("route %s -> %s", name, g.Routes[name]))
	}
	return Configuration{Lines: lines}
}

func Generate(c Configuration) File {
	contents := []byte(strings.Join(c.Lines, "\n") + "\n")
	sum := sha256.Sum256(contents)
	return File{
		Name:     "/etc/nginx/conf.d/routes.conf",
		Hash:     hex.EncodeToString(sum[:]),
		Contents: contents,
	}
}

type Deployment struct {
	version string
	apply   func(File) error
}

func (d *Deployment) Update(file File) (changed bool, err error) {
	if file.Hash == d.version {
		return false, nil
	}
	if err := d.apply(file); err != nil {
		return true, err
	}
	d.version = file.Hash
	return true, nil
}

func main() {
	g := Graph{Routes: map[string]string{"cart": "cart-svc", "pay": "pay-svc"}}
	file := Generate(BuildConfiguration(g))
	d := Deployment{apply: func(f File) error {
		fmt.Printf("apply %s:\n%s", f.Name, f.Contents)
		return nil
	}}
	changed, err := d.Update(file)
	fmt.Printf("first changed=%v err=%v\n", changed, err)
	changed, err = d.Update(file)
	fmt.Printf("again changed=%v err=%v\n", changed, err)
}
```

运行：

```bash
go run main.go
```

第二次 `Update` 应输出 `changed=false`。示例只有一个文件和一个同步 apply 函数；NGF 实际会生成多文件、广播到多个 Pod，并异步经 gRPC 交互，但一次广播会等待订阅者应答后才结束。

### Demo 的四个可迁移模式

1. **模型与渲染分离**：先形成 Configuration，再模板化；
2. **确定性输出**：排序 map key，保证 hash 稳定；
3. **内容去重**：相同版本不触发副作用；
4. **成功后提交版本**：apply 失败不能假装已部署。

## 3. 入口：一个事件批次只触发一次下游

`internal/framework/events/loop.go:EventLoop.Start` 先处理 first batch，再循环交付普通批次。`internal/controller/handler.go:eventHandlerImpl.HandleEventBatch` 对批内事件逐个 `parseAndCaptureEvent`，之后只调用一次：

```go
gr := h.processor.Process(ctx)
h.sendNginxConfig(ctx, logger, gr)
```

若 Graph 为 nil，`sendNginxConfig` 直接返回。这与“Graph 存在但没有可配置 Gateway”不同，后者仍可能需要更新 status 或 finalizer。

## 4. sendNginxConfig 的保护门

源码：`internal/controller/handler.go:sendNginxConfig`。

它不是无条件生成文件，而是依次处理：

1. 重建 WAF poller，并通过 defer 保证收尾；
2. 协调 finalizer；
3. 无 Gateway 时只更新 status；
4. 为每个 Gateway 启动 provision 流程；
5. Gateway 无有效 Listener 时只写 status；
6. WAF bundle pending 且 fail-closed 时暂缓配置；
7. 获取/创建与 Gateway 对应的 Deployment；
8. 构建 Configuration、查 deployment context、记录 latest config；
9. 收集 volume mount，在 `Deployment.FileLock` 内更新配置；
10. 把配置与 upstream 错误加入 status queue。

因此“没有下发”可能是正确的保护行为：对象无效、没有 Listener、WAF 尚未就绪，或内容根本没变化。

## 5. Graph 到 dataplane.Configuration

源码：`internal/controller/dataplane/configuration.go:BuildConfiguration`。

它从 Graph 生成 server、upstream、证书、认证、遥测等数据面结构。Service resolver 通过被索引的 EndpointSlice 找后端地址，连接 [[62-Cache-FieldIndexer与查询成本]] 的查询路径。

边界要点：

- 缺失/不适用的 Graph 会得到默认配置，而非把 nil 传入模板；
- 无效 Route 不应成为有效 location，但仍由 Graph/status 保留；
- Configuration 是 NGINX 语义模型，不应继续暴露所有 Kubernetes 对象细节；
- `BuildConfiguration` 当前返回配置而非 error，部分输入问题已在 Graph 条件中表达。

## 6. Configuration 到文件

源码：`internal/controller/nginx/config/generator.go:Generator.Generate`。

Generator 生成 `[]agent.File`，包括主配置片段、PEM、认证文件、证书 bundle、WAF bundle 等。每个 `agent.File` 有：

```go
type File struct {
	Meta     *pb.FileMeta
	Contents []byte
}
```

`FileMeta` 携带 name、hash、permissions、size。广播只需先发 metadata；Agent 根据 hash 判断并通过 FileService 拉取实际内容，避免把大文件直接塞进通知消息。

> [!warning]
> `Generate` 的契约假定调用方已完成验证。把未经 Graph/Configuration 验证的用户字符串直接送进模板，会把领域错误推迟为 NGINX apply 错误，反馈更慢也更难定位。

## 7. Deployment.SetFiles 如何去重

源码：`internal/controller/nginx/agent/deployment.go:SetFiles` 与 `rebuildFileOverviews`。

在持有 `FileLock` 时：

1. 保存文件内容和 volume mount；
2. 从文件构建只含 metadata 的 overview；
3. 静态文件和用户挂载文件标为 unmanaged，防止 Agent 删除；
4. 由 overview 生成 config version；
5. 与旧 version 相同则返回 nil；
6. 变化时返回 `ConfigApplyRequest` 广播消息。

`internal/controller/nginx/agent/agent.go:NginxUpdaterImpl.UpdateConfig` 收到 nil message 就不发送；有变化则调用 deployment broadcaster。

这里去重的是“所有文件 overview 的配置版本”，不是只比较 `nginx.conf`。权限、路径、hash 的变化都可能改变版本。

## 8. 广播为何能汇总 Pod 结果

源码：`internal/controller/nginx/agent/broadcast/broadcast.go`。

publisher 在每次 Send 时快照当前 listeners，为每个 listener 启动并发发送，然后等待 response channel；`WaitGroup` 全部完成后 Send 才返回。context 取消可以解除等待。

这带来两个语义：

- 同一 Deployment 的多个已订阅 Pod 同时收到版本；
- `UpdateConfig` 返回时，当前 listeners 已成功应答、失败应答或因连接/context 退出。

它不是分布式原子提交：某些 Pod 可能成功、另一些失败。Deployment 用 `podStatuses map[string]error` 保留每个 Pod 的最近结果，并用 `errors.Join` 汇总。

## 9. Agent 如何取得真正的文件内容

`internal/controller/nginx/agent/command.go:Subscribe` 在持有 `FileLock` 的事务边界内订阅消息，并处理初始配置，避免“读取初始配置”和“注册订阅”之间漏掉更新。

收到 ConfigApplyRequest 后：

1. 控制面向 Agent 发送文件 overview 和 config version；
2. Agent 调用 `internal/controller/nginx/agent/file.go:fileService.GetFile` 或 `GetFileStream`；
3. FileService 通过连接找到 Deployment，再按 name + hash 调用 `Deployment.GetFile`；
4. 大文件可按 2 MiB chunk 流式发送；
5. Agent 应用配置并回复；
6. CommandService 清除或记录 Pod error，再通知 broadcaster 的 response channel。

控制面代码并不在本进程里执行 `nginx -s reload`；实际应用由 NGINX Agent 完成。排障时要把控制面生成/传输与 Agent/NGINX 执行分开。

`FileLock` 覆盖 ConfigApply 事务，是因为文件 overview 发出后，Agent 随即按 hash 拉内容；若中途文件 slice 被下一次更新替换，会出现 metadata 与内容版本不一致。

## 10. 错误如何返回 Gateway status

Deployment 维护：

- `podStatuses`：每个 Pod 最近一次结果；
- `latestConfigError`：本轮任一 ConfigApply 失败；
- `latestUpstreamError`：本轮任一 Plus upstream API 失败。

`NginxUpdaterImpl.UpdateConfig` 在广播后把 `GetConfigurationStatus()` 写入 latest config error；handler 随后读取这些值并加入 status queue。

为什么既要 map 又要 latest error？同一事件后续成功操作可能覆盖某 Pod 状态，本轮早先发生的失败仍应进入本轮 Gateway status，不能被“最后一次成功”抹掉。

## 11. NGINX Plus 的第二条路径

OSS 主要通过配置文件 ConfigApply。NGINX Plus 还可在完整配置后调用 `UpdateUpstreamServers`，通过 API action 更新 upstream server，减少全量 reload。

实现会比较 action，未变化则跳过；多个请求错误合并并写 `latestUpstreamError`。因此排障必须区分：

- 文件配置应用失败；
- 文件成功但 Plus upstream API 失败；
- 二者都成功但 status 写回失败。

三者的责任层和重试策略不同。

## 12. 故障定位跳表

| 现象 | 首查位置 | 关键问题 |
|---|---|---|
| Route 未进入配置 | Graph/Configuration | 是否 Accepted、是否附着 Listener |
| 每次事件都下发 | Generator/SetFiles | 输出是否确定，hash/version 是否变化 |
| 完全不广播 | `SetFiles` / updater | message 是否因版本相同为 nil |
| 一个 Pod 失败 | Command/Deployment status | 该连接的 apply response 是什么 |
| Agent 报文件不存在 | FileService | name/hash 是否与锁内内容一致 |
| 所有 Pod 卡住 | broadcaster | listener 是否应答，context 是否可取消 |
| Plus 后端未更新 | upstream actions | action diff 与 API error |

## 13. 源码证据与测试入口

- `internal/controller/handler.go:HandleEventBatch`、`sendNginxConfig`、`updateNginxConf`；
- `internal/controller/dataplane/configuration.go:BuildConfiguration` 与 `internal/controller/nginx/config/generator.go:Generate`；
- `internal/controller/nginx/agent/deployment.go:SetFiles`、`agent.go:UpdateConfig`、`broadcast/broadcast.go:Send`；
- `internal/controller/nginx/agent/command.go:Subscribe`、`file.go:GetFile`、`GetFileStream`。

对应测试：`internal/controller/handler_test.go`、`internal/controller/dataplane/configuration_test.go`、`internal/controller/nginx/config/generator_test.go`、`internal/controller/nginx/agent/deployment_test.go`、`broadcast/broadcast_test.go`、`command_test.go`、`agent_test.go`。

## 14. 练习与检查点

1. 删除 Demo 的 `sort.Strings`，多运行几次并解释它为何可能产生不同内容顺序。
2. 让 apply 第一次失败，测试 version 不更新、下一次相同文件仍会重试。
3. 设计两个 Pod 一成一败时的聚合状态，说明为什么不等价于事务回滚。
4. 画出 metadata 通知与 FileService 内容拉取之间的锁边界。
5. 从 `HTTPRoute` 选一个 hostname，一路追到生成文件中的 server_name，并记录每次字段变换。

检查点：你应能判断问题位于“对象事件、Graph、Configuration、模板文件、版本去重、广播连接、Agent apply、status”中的哪一段，并找到对应测试，而不是只说“配置没生效”。

## 延伸阅读
继续阅读 [[49-EventLoop批处理与状态所有权]]、[[64-ChangeProcessor幂等与增量重建]]、[[38-errors-Join多错误聚合]]。
