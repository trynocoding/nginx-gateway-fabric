---
title: "44 context.Context 的传递和取消"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "918d0fa7"
sources:
  - repo: nginx-gateway-fabric
    revision: "918d0fa7"
    dirty: false
---

# 44 context.Context 的传递和取消

> [!abstract]
> `Context` 是调用树的控制面：传递 deadline、取消广播、稳定的终止错误和请求域值。它不会杀死 goroutine；只有代码在阻塞点或循环中观察 `Done`/`Err`，取消才真正生效。派生者负责调用 cancel 释放子树资源。

## 学习目标与前置

- 逐方法掌握 `Deadline`、`Done`、`Err`、`Value` 的签名、状态和 nil/关闭语义；
- 核实 Go 1.26 的构造、取消原因、脱离取消与回调 API；
- 建模取消树、时间预算、幂等 cancel 与 value 链；
- 完整追踪 DeploymentBroadcaster 取消树和 gRPC interceptor 值链。

前置：[[40-goroutine启动与退出责任]]、[[41-channel方向与所有权]]、[[43-select多路复用]]。

## 1. 最小心智模型：不可变链 + 可关闭信号

`Context` 是接口值，派生函数返回一个新节点。父节点取消会向所有仍连接的后代传播；取消子节点不会反向取消父节点，也不会影响兄弟节点。值和 deadline 沿父链查找，越近的节点优先。

**Go 1.26 接口原样签名：**

```go
type Context interface {
	Deadline() (deadline time.Time, ok bool)
	Done() <-chan struct{}
	Err() error
	Value(key any) any
}
```

四方法可被多个 goroutine 并发调用。它们不暴露 `Cancel`；取消能力由构造函数单独返回给拥有者，避免任何拿到 context 的被调用者都能终止上游。

## 2. 四方法逐一吃透

### 2.1 `Deadline() (deadline time.Time, ok bool)`

签名中的 `ok` 表示是否存在 deadline；`ok=false` 时不要解释返回的 `time.Time`。连续调用返回相同结果。

```go
if deadline, ok := ctx.Deadline(); ok {
	remaining := time.Until(deadline)
	if remaining <= 0 {
		return ctx.Err()
	}
}
```

状态规则：

| context | `Deadline` |
|---|---|
| `Background`/`TODO` | 零时间，`false` |
| `WithDeadline(parent, d)` | `min(parentDeadline, d)`，`true` |
| `WithTimeout(parent, x)` | 等价于 `WithDeadline(parent, time.Now().Add(x))` |
| `WithoutCancel(parent)` | 零时间，`false`，即使 parent 有 deadline |

deadline 是“最晚允许工作到何时”，不是让 goroutine 自动停止的定时器回调。被调用代码仍要观察 `Done`，下游 I/O 也要接收这个 context。

### 2.2 `Done() <-chan struct{}`

`Done` 返回只收 channel。可取消 context 在取消后关闭它；这是广播，不发送任何值。连续调用返回同一个 channel。

```go
select {
case result := <-results:
	return result, nil
case <-ctx.Done():
	return Result{}, ctx.Err()
}
```

关键状态：

- `Background().Done()` 与 `TODO().Done()` 是 `nil`；单独接收会永久阻塞，放在 `select` 中等于禁用该 case；
- 可取消 context 在尚未取消时返回非 nil、未关闭 channel；
- 取消后 channel 被关闭，因此所有当前和未来接收都立即完成；
- `CancelFunc` 返回与 `Done` 真正关闭之间允许存在极短异步窗口；不要用“刚 cancel 后 default 分支一定看见关闭”做正确性假设；
- `WithoutCancel(parent).Done()` 明确为 `nil`。

`Done` 只有“停止”信号，没有原因；原因来自 `Err`/`Cause`。

### 2.3 `Err() error`

只要 `Done` 尚未关闭，`Err()` 就返回 `nil`。结束后只返回两个稳定哨兵之一：

| 终止方式 | `Err()` |
|---|---|
| 显式 cancel 或父取消 | `context.Canceled` |
| 自己或父 deadline 到期 | `context.DeadlineExceeded` |

一旦变为非 nil，后续调用返回同一结果。使用 `errors.Is(err, context.Canceled)` 或 `errors.Is(err, context.DeadlineExceeded)` 判断；不要比较错误字符串。

`Err` 故意只提供稳定类别。业务原因使用 `context.Cause(ctx)`；即使 cause 是 `database unavailable`，`ctx.Err()` 仍是 `context.Canceled`。

### 2.4 `Value(key any) any`

`Value` 从当前节点向父链查找相等 key，找不到返回 nil；同一 key 的近端值遮蔽远端值。

```go
type requestIDKey struct{}

func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, requestIDKey{}, id)
}

func RequestID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(requestIDKey{}).(string)
	return id, ok
}
```

key 必须可比较；包应使用未导出的自定义类型，不能用裸 string，以免跨包碰撞。导出“构造器 + typed accessor”，调用者不直接依赖 key。

`Value` 仅放跨 API 边界的请求域元数据，如 trace ID、认证主体。不要放可选参数、logger 配置大包、数据库连接或可变业务状态；这些应是显式参数/依赖。

## 3. Go 1.26 API 地图

### 根节点

- `context.Background()`：非 nil、永不取消、无 deadline、无 value；main、初始化、测试的顶层根；
- `context.TODO()`：相同运行语义，但表达“调用链尚未接入正确 context”的代码意图。

二者不是随手丢弃上游 context 的借口。函数已经收到 `ctx` 时，继续传它。

### 普通取消

```go
ctx, cancel := context.WithCancel(parent)
defer cancel()
```

`WithCancel(parent)` 返回 child 和 `CancelFunc`。调用 cancel 会：取消 child 和后代、从 parent 移除 child 引用、停止关联 timer。`CancelFunc` 不等待 goroutine 退出；可被多个 goroutine 并发调用，第一次之后幂等无效果。

### 带原因取消

```go
ctx, cancel := context.WithCancelCause(parent)
cancel(errors.New("peer rejected update"))
fmt.Println(ctx.Err())         // context canceled
fmt.Println(context.Cause(ctx)) // peer rejected update
```

`cancel(nil)` 的 cause 是 `context.Canceled`。第一次到达节点的取消决定 cause：父先取消，子继承父 cause；子先以 cause2 取消，则子保留 cause2，父以后仍有自己的 cause1。

### deadline 与 timeout

```go
ctx1, cancel1 := context.WithDeadline(parent, deadline)
defer cancel1()

ctx2, cancel2 := context.WithTimeout(parent, 500*time.Millisecond)
defer cancel2()
```

父 deadline 更早时，子不能扩展预算。即使操作提前完成，也要 cancel，及时释放 timer 与父对子节点的引用。

带原因版本：

```go
ctx, cancel := context.WithTimeoutCause(parent, time.Second, ErrBudget)
defer cancel()
```

`WithDeadlineCause`/`WithTimeoutCause` 只在 deadline 自然到期时设置给定 cause；返回的是普通 `CancelFunc`，提前调用它不会设置该 cause。

### `Cause`

`context.Cause(ctx)`：未取消为 nil；普通取消等于 `ctx.Err()`；cause cancel 返回业务错误。API 边界通常先返回 `ctx.Err()` 保持稳定分类，日志/诊断可记录 `Cause`。

### `WithoutCancel`

```go
detached := context.WithoutCancel(parent)
```

它保留 parent 的 value 查找链，却切断取消、deadline 和 cause：`Done()==nil`、无 deadline、`Err()==nil`、`Cause()==nil`。适用于请求结束后仍必须完成的短清理/审计，但必须再加自己的 timeout，否则把有界任务变成无界任务。

### `AfterFunc`

**说明性示例：** `stop := context.AfterFunc(ctx, func() { close(resource) })`。

context 取消后，`f` 在自己的 goroutine 执行；已取消 context 会立即异步启动。多个注册彼此独立。`stop()` 返回 false 表示回调已开始或已被停止，且它不等待回调结束；如需完成证明，要另加 channel/WaitGroup。`f` 必须自身并发安全和幂等。

### 非 nil 父节点

Go 1.26 的 `WithCancel`、`WithCancelCause`、deadline/timeout、`WithValue`、`WithoutCancel` 都要求非 nil parent；传 nil 会 panic。公共 API 也不应接受 nil context，尚不确定时传 `TODO()`。

## 4. 可独立运行 demo：预算、原因、值和协作退出

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"time"
)

type jobKey struct{}

func work(ctx context.Context) error {
	job, _ := ctx.Value(jobKey{}).(string)
	select {
	case <-time.After(200 * time.Millisecond):
		fmt.Println("finished", job)
		return nil
	case <-ctx.Done():
		return fmt.Errorf("%s: %w; cause=%v", job, ctx.Err(), context.Cause(ctx))
	}
}

func main() {
	root := context.WithValue(context.Background(), jobKey{}, "reload")
	ctx, cancel := context.WithCancelCause(root)
	done := make(chan error, 1)
	go func() { done <- work(ctx) }()

	time.Sleep(10 * time.Millisecond)
	cancel(errors.New("shutdown requested"))
	cancel(errors.New("second cause is ignored"))
	fmt.Println(<-done)
}
```

```bash
gofmt -w main.go && go run main.go
# reload: context canceled; cause=shutdown requested
```

该 demo 同时证明：value 向下可见、取消需 worker 配合、cancel 不 join、第一次 cause 获胜、error 仍需显式返回通道。

## 5. 常用生产模式

| 模式 | 可迁移规则 |
|---|---|
| 首参传播 | `func Load(ctx context.Context, key string)`；不要存 struct |
| 预算递减 | 传播 parent 或缩短 deadline；不用 `Background` 重置预算 |
| 阻塞可取消 | send/receive/重试/I/O 均观察 `Done` |
| cancel + wait | 派生者 cancel；启动者另定义完成证明；Cancel 不是 Wait |
| typed accessor | 私有 key + `NewContext`/`FromContext`，缺失显式返回 |

## 6. NGF 追踪一：DeploymentBroadcaster 取消树

具体触发是 deployment 构造；终端效果是父 shutdown 或 listener 退订能解开 publisher 的发送/ACK 等待。

| 阶段 | 符号 | 状态/边界 | 失败与退出 |
|---|---|---|---|
| 构造 | `NewDeploymentBroadcaster(ctx)` | `WithCancel(ctx)` 建 broadcaster child | parent 必须非 nil |
| 启动 | 同上 | 启动 subscriber、publisher 两 goroutine | 构造器无公开 Wait |
| 订阅 | `Subscribe` | `WithCancel(broadcasterCtx)` 建 listener child | broadcaster Done 时不登记 |
| 发布 | `publisher` | snapshot listeners；每 listener `wg.Go` | 每个发送 select 同时监听两层 Done |
| ACK | `publisher` | 等 `responseCh` | listener 或 broadcaster cancel 均解锁 |
| 退订 | `CancelSubscription` → `subscriber` | 先 `channels.cancel()` 再 delete | 只取消一个 listener，不伤兄弟 |
| shutdown | parent cancel 或 subscriber return | `broadcasterCancel()` 关闭整棵子树 | `Send` 返回 false，workers 退出 |

源码不使用 `close(listenCh)`：一个 listener context 能同时控制发送和等 ACK；全局 context 能统一控制所有 listener。`broadcast_test.go` 验证 parent cancel、消息已收/未收时退订都不会永久阻塞。

> [!warning]
> `publisher` 的 `wg.Wait()` 本身没有 context 参数；它之所以能结束，是每个 worker 的所有阻塞点都有 listener/broadcaster Done 分支。迁移时漏掉任一阻塞点，整个 Wait 就会泄漏。

## 7. NGF 追踪二：gRPC interceptor → handler 的值链

这里 Context 同时承担传输取消/deadline和认证后身份值，但职责分层清楚。

### 构造与运行路径

1. gRPC runtime 给 interceptor 原始请求 context，其中含 incoming metadata 与 RPC 生命周期取消；
2. `ContextSetter.Unary` 或 `ContextSetter.Stream` 调 `validateConnection`；
3. `getGrpcInfo` 从 metadata 取首个 `uuid`、`authorization`；缺 metadata/identity/auth 立即返回 gRPC error；
4. `validateToken` 用两个 `WithTimeout(ctx, 30s)` 分别约束 Kubernetes TokenReview Create 和 Pod List，并 defer cancel；
5. 认证及 running Pod 校验成功后，`grpcinfo.NewGrpcContext(ctx, GrpcInfo)` 调 `WithValue`；注意它基于原始 `ctx`，保留 RPC 的 deadline/cancel/value 链；
6. unary 把新 ctx 传 `handler(ctx, req)`；stream 不能替换接口参数，因此用 `streamHandler{ServerStream:ss, ctx:ctx}` 覆盖 `Context()`；
7. command/file handler 调 `grpcinfo.FromContext` 取值；缺失返回 `ok=false`，进入各自错误路径。

**NGF 原样源码节选：**

```go
type contextGRPCKey struct{}

func NewGrpcContext(ctx context.Context, r GrpcInfo) context.Context {
	return context.WithValue(ctx, contextGRPCKey{}, r)
}

func FromContext(ctx context.Context) (GrpcInfo, bool) {
	v, ok := ctx.Value(contextGRPCKey{}).(GrpcInfo)
	return v, ok
}
```

这个 typed key 是零大小未导出类型，跨包无法碰撞；handler 依赖访问器而非 key。`context_test.go` 验证存在时值相等、缺失时 `ok=false` 且返回零值；interceptor 测试覆盖元数据与认证失败分支。

## 8. 失败与误区

- context 存 struct：对象与一次调用生命周期混淆；每方法显式传首参；
- 传 nil：派生函数 panic；传 `TODO` 并留下迁移信号；
- 派生后忘 cancel：timer、子引用保留到 parent 结束；
- `cancel()` 后假定 goroutine 已退出：cancel 不等待；另行 join；
- 只检查 `ctx.Err()` 一次：随后阻塞仍可能泄漏；
- 用 value 传配置：依赖不可见且失去类型签名；
- 用 string key：跨包可能遮蔽；
- 每层重设 30 秒 timeout：可能无意扩张总体预算；parent 更早 deadline 会限制 child，但若错误换成 Background 就会失控；
- 滥用 `WithoutCancel`：后台任务失去上界；必须再套新 timeout；
- 把 Cause 直接暴露给不可信客户端：业务错误可能泄漏内部信息，应映射边界错误。

## 9. 迁移边界

可直接迁移：首参传播、typed accessor、派生即 defer cancel、每阻塞点监听 Done、稳定错误分类与诊断 cause 分离。

有条件迁移：Broadcaster 的 listener 子树适合“独立订阅可单独取消”；若任一 listener 失败应取消全组，需要不同的组错误策略。gRPC value 模式适合认证主体，不适合业务配置。

不要照搬：`WithoutCancel` 不能用来“修复”被错误取消的调用链；应先修正生命周期所有权。Context 也不能替代数据 channel、mutex 或 WaitGroup。

## 10. 练习与答案

1. `Background().Done()` 是关闭 channel 还是 nil？——nil；select case 被禁用。
2. `cancel(cause)` 后 `Err` 与 `Cause` 各是什么？——`Canceled` 与首次 cause。
3. child 设 10 秒、parent 剩 2 秒，实际 deadline？——parent 的较早 deadline。
4. 为什么仍要 `defer cancel()`？——提前完成时释放 timer、父引用与后代。
5. `WithoutCancel` 保留什么？——value 链；不保留取消、deadline、Err、Cause。
6. `AfterFunc` 的 stop=false 是否表示回调已完成？——否，只表示未成功阻止；要自行等待。
7. Broadcaster 退订 A 会取消 B 吗？——不会；A 是独立 child。取消 broadcaster 才级联全部。
8. stream interceptor 为什么包装 `ServerStream`？——gRPC stream handler 从 `ServerStream.Context()` 取 context，需覆盖该方法传递新值链。

## 验证与源码证据索引

- **版本事实** Go 1.26.0 `$GOROOT/src/context/context.go` 与 `go doc -all context`
- **源码事实** `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster,Subscribe,subscriber,publisher`
- **测试佐证** `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go`
- **源码事实** `ngf:internal/controller/nginx/agent/grpc/interceptor/interceptor.go:Unary,Stream,validateConnection,validateToken`
- **源码事实** `ngf:internal/controller/nginx/agent/grpc/context/context.go:NewGrpcContext,FromContext`
- **源码事实** `ngf:internal/controller/nginx/agent/command.go:Subscribe` 与 `file.go` 的 consumers
- **测试佐证** `ngf:internal/controller/nginx/agent/grpc/context/context_test.go:TestGrpcInfoInContext,TestGrpcInfoNotInContext`

demo 验证命令：`gofmt -w main.go && go run main.go`。项目包验证见文末交付记录。

下一步：[[45-timeout-timer与ticker生命周期]]、[[47-WaitGroup与fan-out-fan-in]]、[[49-EventLoop批处理与状态所有权]]。
