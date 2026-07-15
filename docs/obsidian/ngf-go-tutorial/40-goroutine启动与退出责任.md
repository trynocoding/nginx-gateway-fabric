---
title: "40 goroutine 的启动与退出责任"
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

# 40 goroutine 的启动与退出责任

> [!abstract]
> `go f()` 只负责启动。完整并发设计还必须回答：谁要求退出、每个阻塞点怎样解除、谁等待结束、错误送到哪里。通常“启动者拥有生命周期”。

## 学习目标与前置

- 理解 goroutine 没有返回值通道、没有自动 join；
- 为任务定义 start/stop/wait/error 四项责任；
- 避免 goroutine 泄漏、静默错误和关闭竞态；
- 追踪 `DeploymentBroadcaster` 的 subscriber/publisher/worker 生命周期。

前置：[[19-函数值闭包与高阶函数]]、[[20-defer与资源清理]]。

## 1. 语法与心智模型

```go
go work() // 调用在新 goroutine 执行；当前调用者立即继续
```

goroutine 与函数调用共享进程内存，但调度顺序未定义。函数的返回值会被丢弃，因此需要 channel、共享状态或回调传结果。main 返回时，其他 goroutine 不会自动完成。

生命周期清单：

| 责任 | 常用机制 |
|---|---|
| 启动 | 构造器、Run/Start |
| 停止请求 | `context.CancelFunc`、关闭 stop channel |
| 协作退出 | 每个阻塞 select 都监听 `ctx.Done()` |
| 等待 | `WaitGroup`、done channel、阻塞的 Start |
| 错误 | error channel、errgroup、Start 返回 error |

## 2. 可独立运行 demo

**可运行 demo（Go 1.26.0）：**

```go
package main

import (
	"context"
	"fmt"
	"sync"
)

type Service struct {
	cancel context.CancelFunc
	wg     sync.WaitGroup
	errs   chan error
}

func Start(parent context.Context) *Service {
	ctx, cancel := context.WithCancel(parent)
	s := &Service{cancel: cancel, errs: make(chan error, 1)}
	s.wg.Go(func() {
		defer close(s.errs)
		select {
		case <-ctx.Done():
			return
		case s.errs <- fmt.Errorf("worker failed"):
			return
		}
	})
	return s
}

func (s *Service) Stop() {
	s.cancel()
	s.wg.Wait()
}

func main() {
	s := Start(context.Background())
	fmt.Println(<-s.errs)
	s.Stop()
}
```

```bash
gofmt -w main.go && go run main.go
# worker failed
```

## 3. 常用模式

### 阻塞式 Run

`Run(ctx) error` 由调用者 `go` 启动或直接阻塞；生命周期和错误最清晰。

### 构造即启动

构造器启动内部 goroutine 时，返回对象必须暴露 Stop/Wait，或明确绑定父 context。

### worker pool

启动者创建输入 channel、固定 worker、WaitGroup；发送者停止后由拥有者关闭输入，workers range 退出。

### fan-out/fan-in

每项并发处理，Wait 汇合；错误和取消策略必须额外定义，详见 [[47-WaitGroup与fan-out-fan-in]]。

### ownership capsule

把 context、cancel、WaitGroup 和唯一错误结果封装在服务对象内；`Start` 只启动，`Stop` 只发取消，`Wait` 只汇合。需要允许多次 Stop 时依赖 `CancelFunc` 幂等；需要多次 Wait 时缓存最终 error，而不是让多个调用者竞争一次性 error channel。

## 4. NGF：DeploymentBroadcaster

**NGF 缩写源码（非独立 demo）：**

```go
broadcasterCtx, cancel := context.WithCancel(ctx)
go broadcaster.subscriber()
go broadcaster.publisher()
```

责任关系：

1. `NewDeploymentBroadcaster` 是启动者，派生受控子 context；
2. subscriber/publisher 的每个主 select 都监听 `broadcasterCtx.Done()`；
3. subscriber defer cancel，退出会级联取消 listener contexts；
4. publisher 每个 listener 用 `wg.Go`，发送和等 ACK 都监听 listener/broadcaster 取消；
5. `wg.Wait` 后才通过 `doneCh` 解除 `Send`；
6. 错误不是 channel；`Send` 收到 done 后才 RLock 采样 **live registry** 的 `len(listeners)>0`，取消返回 false。该 bool 不证明本批 snapshot 有 listener、已交付或已 ACK：并发订阅可让空 snapshot 最后为 true，并发退订可让已 ACK snapshot 最后为 false。接口注释与实现语义存在漂移风险，调用者不应把它当交付结果。

附近测试 `broadcast_test.go` 验证正常发送、多 listener、父 context 取消、订阅取消在发送前/等 ACK 时都能解除阻塞。

> [!warning]
> 当前 Broadcaster 没有公开 Wait；父 context 是停止合同，测试通过业务调用完成间接证明退出。若需要严格进程 shutdown 证明，应增加显式 Wait/Close，而不是 sleep。

## 5. 失败模式与边界

- 只发 stop 不等待：资源可能仍在使用；
- channel 发送没有取消 case：消费者消失后永久阻塞；
- goroutine 返回 error：结果直接丢失；
- worker panic：无法被别的 goroutine recover；
- 循环使用 `time.Sleep`：取消最多延迟一个 sleep；
- 构造函数启动 goroutine，却允许传 nil context：立即制造不可控生命周期。

选择 goroutine 是为并行等待多个 listener；subscriber/publisher 是串行所有者循环。若任务只有一次快速计算，普通调用更清楚。迁移到 errgroup 适合“任一失败取消全组”；当前 listener 取消彼此独立，不应机械替换。

## 6.1 启动、退出、等待、错误矩阵

| 形状 | 谁启动 | 谁要求退出 | 谁等待 | 错误归宿 |
|---|---|---|---|---|
| 阻塞 `Run(ctx) error` | 调用者 | parent cancel | 直接调用者 | 返回值 |
| 后台 `Start` + `Wait` | 对象构造者 | `Stop`/parent | `Wait` 调用者 | `Wait` 返回 |
| worker pool | pool owner | close input/cancel | owner 的 WaitGroup | 聚合或首错 |
| fire-and-forget | 进程级 owner | 进程 context | 通常无 | 必须日志/指标 |

fire-and-forget 只适用于错误不影响调用结果、生命周期严格绑定进程、且可观测的辅助任务。请求域业务任务不应在 handler 返回后无主运行。

### 错误与 shutdown 同时发生

必须定义谁获胜：常见选择是记录第一个业务错误并 cancel 兄弟；若只因 parent shutdown 退出，则返回 `ctx.Err()` 或 nil 取决于 API 合同。不要让一个 goroutine阻塞发送 error：错误通道通常容量 1，或由单一 coordinator 收集。

> [!tip]
> 代码审查时对每个 `go` 关键字反向询问四件事：退出信号在哪里、所有阻塞点是否可解除、完成证明在哪里、panic/error 谁接住。任一答案缺失，都可能是生命周期漏洞。

## 7. 练习与检查点

1. 为 demo 增加 `Wait() error`，避免直接读 errs。
2. 找出 Broadcaster publisher 中所有可能阻塞点及取消分支。
3. 若一个 listener 永不 ACK，什么事件能解除它？

答案：发送 listenCh、等待 responseCh 都有 listener/global cancel；发送 doneCh 只有 global cancel。listener 取消或父 context 取消可解除第 3 题。等待接口应只由一个位置消费 error，并在 worker 完成后返回。

## 源码证据索引

- `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:NewDeploymentBroadcaster`
- `ngf:internal/controller/nginx/agent/broadcast/broadcast.go:subscriber,publisher,Send`
- `ngf:internal/controller/nginx/agent/broadcast/broadcast_test.go`

下一步：[[41-channel方向与所有权]]、[[44-context传递与取消]]、[[47-WaitGroup与fan-out-fan-in]]。
