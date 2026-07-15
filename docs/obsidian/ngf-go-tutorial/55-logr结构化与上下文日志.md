---
title: "55 logr 结构化与上下文日志"
tags: [nginx-gateway-fabric, go-1-26, source-analysis, tutorial]
status: complete
note_type: tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 55 logr 结构化与上下文日志

> [!abstract] 核心结论
> logr 把消息与 `key,value` 字段分开，logger value 本身不可变式派生：`WithName` 增加组件名，`WithValues` 绑定稳定上下文，`V(n)` 选择详细度。请求/调和日志应从 context 取框架已注入字段，并严格避免 Secret、token、证书私钥和完整配置内容。

## 学习目标与前置

前置：[[18-可变参数]]、[[44-context传递与取消]]。完成后应能：

- 正确调用 `Info/Error/V/WithName/WithValues`；
- 保持 key 为 string、参数成对、字段名稳定；
- 用 `logr.NewContext/FromContextOrDiscard` 传播日志上下文；
- 区分 V-level 与业务严重级别；
- 读懂 NGF EventLoop 如何为 batch 派生 logger 并传给 handler。

## 1. 基础 API

```go
logger.Info("reconciled", "namespace", ns, "name", name)
logger.Error(err, "failed to reconcile", "name", name)
```

消息描述事件，字段提供可筛选上下文。不要用 `fmt.Sprintf` 把所有值塞进 message；那会丢结构。`Error` 显式接收 error，不等于 `V(0)`，也不受普通 verbosity 过滤方式支配。

key/value 必须成对，key 应是 string。具体 sink 会处理奇数参数/非 string key，但不应依赖它的修复文本；封装 helper 时尤其要保持偶数。

## 2. 可独立运行 demo

**可运行示例（Go 1.26.0；依赖仓库锁定的 `github.com/go-logr/logr`）：**

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-logr/logr"
	"github.com/go-logr/logr/funcr"
)

func main() {
	logger := funcr.New(
		func(prefix, args string) { fmt.Println(prefix, args) },
		funcr.Options{Verbosity: 1, LogTimestamp: false},
	).WithName("controller").WithValues("gateway", "demo")

	logger.Info("starting", "workers", 2)
	logger.V(1).Info("cache detail", "entries", 3)
	logger.V(2).Info("not emitted")

	ctx := logr.NewContext(context.Background(), logger.WithValues("request", "r-1"))
	logr.FromContextOrDiscard(ctx).Info("handled")
}
```

把代码保存为单个 Go 文件，在本仓库模块中执行 `go run <文件>`，会输出 V(0)、V(1) 和 context 日志，不输出 V(2)。已在本仓库 `go1.26.0` 与锁定 logr 依赖下执行验证。

## 3. Verbosity 不是“数值越大越严重”

`logger.V(0)` 是默认信息，`V(1)` 更详细，数字越大越啰嗦、越可能被过滤。选择建议：

- V(0)：生命周期变化、用户可行动的重要状态；
- V(1)：每次 reconcile/batch、正常重试与调试字段；
- 更高：高频内部细节，需确认项目 sink 配置。

错误不应因为想减少噪声就改成高 V；应先判断它是否预期、是否已在上层统一记录，避免同一 error 每层重复打一遍。

## 4. WithName 与 WithValues

`WithName("eventHandler")` 返回派生 logger，名称通常由 sink 拼成层级。组件构造时绑定一次比每行重复 `component` 字段更清楚。

`WithValues("policy", nsName)` 也返回新 logger，后续每条日志带该字段。适合在对象/请求生命周期内稳定的值；不断变化的值应放单次 Info 中，避免派生 logger 的上下文与现实脱节。

logger 是轻量 value，可安全传递；sink 的并发安全由 logr 契约/实现承担。不要把 `WithValues` 理解为修改原 logger。

## 5. Context 日志

`logr.NewContext(ctx,logger)` 创建携带 logger 的 child context；`FromContextOrDiscard` 在不存在 logger 时返回丢弃 logger。controller-runtime 常用自己的 `log.FromContext(ctx)`，并在调用 Reconciler 前预置资源 group/kind/namespace/name。

规则：

- context 仍应作为第一个参数传播，不能只传 logger 丢取消/截止时间；
- library 不应擅自用 Background 替换传入 ctx；
- 不要把 logger 塞进自定义 untyped key，优先库提供的 NewContext；
- request 结束后不要让后台任务无限持有整个 context。

## 6. NGF 主实例：EventLoop batch logger

`internal/framework/events/loop.go:EventLoop.Start` 在每次 batch 启动时：

```go
batchLogger := el.logger.WithName("eventHandler").WithValues("batchID", el.currentBatchID)
batchLogger.V(1).Info("Handling events from the batch", "total", len(batch))
el.handler.HandleEventBatch(ctx, batchLogger, batch)
batchLogger.V(1).Info("Finished handling the batch")
```

**生产源码节选。** 名称标识组件，batchID 是贯穿这一批的稳定关联字段，total 是单条开始事件的字段。同一个派生 logger 传给 handler，使下游日志自动关联 batch，而无需全局变量。

`internal/framework/events/loop_test.go` 主要验证 batch/取消行为，使用 `logr.Discard`，没有断言格式；日志 backend 输出格式不应成为核心逻辑测试依赖。

## 7. 另一个边界：Reconciler 从 context 取日志

`internal/framework/controller/reconciler.go:Reconcile` 使用 controller-runtime 的 `log.FromContext(ctx)`。注释明确框架已附加资源身份，所以方法不重复设置这些字段。这避免字段冲突，也说明“谁建立 context logger”属于框架边界。

管理器 wiring 大量使用 `cfg.Logger.WithName("generator")`、`WithName("eventLoop")` 等，为长期组件建立名称；WAF poller 用 `WithValues("policy", cfg.policyNsName)` 固定对象上下文。

## 8. 字段设计

稳定 key 比漂亮 message 更重要：

- 使用 `namespace/name` 两字段还是 NamespacedName 一个值，要在项目内一致；
- 数字保持数字，bool 保持 bool，不提前 fmt 成 string；
- error 传给 Error 的第一个参数；额外错误若是业务字段再命名；
- 高基数字段会增加日志/指标后端成本；
- 日志不是审计记录，除非系统另有完整性与保留保证。

## 9. 敏感信息边界

> [!danger] 结构化不代表可以记录更多数据
> 禁止记录 Kubernetes Secret Data、JWT/license、用户名密码、私钥、完整证书 bundle、Authorization header、完整生成配置。

可记录经过威胁模型审核的 resource key、错误类别、受控状态、长度。hash 也可能成为稳定关联标识或敏感材料指纹，只有确有诊断需要才记录。Error 文本可能包含 URL/token 等上游数据，包装和打印前也要审计。

## 10. 常见误区与迁移边界

- `V(1).Info("error", "error", err)` 不等于 `Error(err,...)`；
- 同一 error 在底层和上层重复记录会制造噪声；通常底层返回带上下文 error，由有操作语义的边界记录一次；
- logger 名称与字段不是 context cancellation 的替代品；
- 测试业务结果优先，只有日志本身是用户契约时才捕获 sink。

**直接迁移：** 组件 WithName、请求 WithValues、字段化消息。**条件迁移：** context logger 取决于框架约定。**不要复制：** 打印完整对象图或 Secret 方便调试。

## 11. 练习与检查点

1. 在 demo 把 Verbosity 改 0，检查 V(1) 也被过滤。
2. 构造奇数 key/value 调用，观察 sink 如何修复；再恢复正确调用，不把修复行为当契约。
3. 审计一个 NGF error log：列出字段、基数、是否可能含 Secret/URL/query。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| batch 派生日志 | `internal/framework/events/loop.go:EventLoop.Start` |
| context logger | `internal/framework/controller/reconciler.go:Reconcile` |
| 组件命名 wiring | `internal/controller/manager.go` 的 `Logger.WithName` 调用 |
| 对象稳定字段 | `internal/framework/waf/poller/poller.go:newPoller` |

上一章：[[54-reflect与运行时类型注册]] · 下一章：[[56-go-generate与生成代码边界]]
