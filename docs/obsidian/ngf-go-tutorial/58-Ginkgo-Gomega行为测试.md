---
title: "58 Ginkgo/Gomega 的行为测试组织"
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

# 58 Ginkgo/Gomega 的行为测试组织

> [!abstract]
> Ginkgo v2 把测试组织成容器节点和可运行的 `It` 节点；Gomega 提供 matcher 与异步断言。NGF 固定使用 Ginkgo `v2.30.0`、Gomega `v1.41.0`。它们仍运行在 `go test` 内，不能跳过标准测试的资源隔离、context 和 race 规则。

## 学习目标与前置

- 写 suite bootstrap、`Describe/Context/When/It`；
- 理解树构建阶段与 spec 运行阶段；
- 用 `BeforeEach` 建立每例状态、`DeferCleanup` 回收资源；
- 区分 `Expect`、`Eventually`、`Consistently`；
- 判断何时 Ginkgo 更清楚，何时标准 `testing` 更直接。

前置：[[57-表驱动子测试与并行测试]]、[[43-select多路复用]]。

## 1. Suite 如何接入 `go test`

每个 Ginkgo suite 仍需一个标准测试入口：

```go
func TestDemo(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Demo Suite")
}
```

Ginkgo 在包初始化期间注册声明树，`RunSpecs` 执行叶子 spec。NGF `internal/framework/controller/controller_suite_test.go` 就是 controller suite 入口。

## 2. 容器节点与运行节点

```go
var _ = Describe("Cache", func() {
	Context("when the key exists", func() {
		It("returns the value", func() {})
	})
})
```

- `Describe/Context/When`：组织语境，不是测试本身；
- `It`：可执行 spec，描述一个可观察行为；
- `BeforeEach`：沿祖先链、每个 It 前执行；
- `AfterEach`：每个 It 后执行；优先考虑 `DeferCleanup` 让创建与释放相邻；
- `DescribeTable/Entry`：相同行为的参数化案例。

不要在 `Describe` 闭包的构建阶段执行网络调用或修改全局状态；把运行期 setup 放进 BeforeEach/It。

## 3. 可运行的最小 suite（Go 1.26）

`demo_suite_test.go`：

```go
// 可运行测试的一部分；Go 1.26.0；Ginkgo v2.30.0，Gomega v1.41.0
package demo_test

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestDemo(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Demo Suite")
}
```

`counter_test.go`：

```go
// 可运行测试的一部分；Go 1.26.0
package demo_test

import (
	"context"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("worker", func() {
	var values chan int

	BeforeEach(func() {
		values = make(chan int, 1)
		ctx, cancel := context.WithCancel(context.Background())
		DeferCleanup(cancel)

		go func() {
			select {
			case values <- 42:
			case <-ctx.Done():
			}
		}()
	})

	It("eventually publishes a value", func() {
		Eventually(values).WithTimeout(time.Second).Should(Receive(Equal(42)))
		Consistently(values).WithTimeout(20 * time.Millisecond).ShouldNot(Receive())
	})
})
```

临时模块需固定依赖后执行：

```bash
go mod init example.com/ginkgodemo
go get github.com/onsi/ginkgo/v2@v2.30.0 github.com/onsi/gomega@v1.41.0
gofmt -w '*_test.go'
go test -race -v .
```

## 4. Gomega matcher 心智模型

```go
Expect(err).NotTo(HaveOccurred())
Expect(got).To(Equal(want))
Expect(events).To(HaveLen(2))
Expect(err).To(MatchError(ContainSubstring("timeout")))
```

`Equal` 用深度相等语义，`BeIdenticalTo`/`BeNumerically` 等 matcher 语义不同。断言失败信息应围绕业务结果；不要为了方便对整个巨大对象 Equal，导致差异难读。

### Eventually

反复调用函数或读取 channel，直到 matcher 成功/超时。适合最终一致的异步状态：

```go
Eventually(fake.CallCount).Should(Equal(1))
Eventually(ch).Should(Receive(Equal(event)))
```

### Consistently

在一段时间内 matcher 必须持续成立，适合证明“不应发生事件”。它只能证明观察窗口内未发生，不是永恒保证；窗口应由协议上界支持。

## 5. `DeferCleanup` 与上下文

Ginkgo 的 cleanup 与当前 spec 绑定，支持函数参数注入。NGF `internal/framework/events/loop_test.go`：

```text
BeforeEach 创建 context/cancel 并启动 EventLoop
  → DeferCleanup 接收 SpecContext
  → cancel
  → Eventually(errorCh).WithContext(dctx) 等待 Start 退出
  → 断言退出无错误
```

这比只 `defer cancel()` 更完整：cleanup 不仅发取消，还验证 goroutine 真正结束，避免泄漏影响后续 spec。`NodeTimeout` 给 cleanup 独立上界。

## 6. NGF Reconciler 测试如何组织行为

`internal/framework/controller/reconciler_test.go` 使用外部包 `controller_test`，只通过导出 API 测试：

```text
Describe Reconciler
  BeforeEach：每例新 FakeGetter、无缓冲 eventCh
  Describe Normal cases
    When 无 filter：It upsert / It delete
    When 有 filter
      When not ignored：upsert / delete
      When ignored：Consistently eventCh 不接收
  Describe Edge cases
    getter error
    DescribeTable canceled context
```

异步 helper 在 goroutine 调 `Reconcile`，并 `defer GinkgoRecover()`，把结果写入 channel。测试以 `Eventually(eventCh).Should(Receive(...))` 驱动无缓冲 channel 两端 rendezvous，再接收 reconcile 结果。

`BeforeEach` 只建立每例共享 fixture，具体 Getter 行为在 It/helper 中设置。这样上下文层级表达“有无过滤器”，而不是复制整套断言。

## 7. 标准 testing 与 Ginkgo 的边界

| 场景 | 更合适 |
|---|---|
| 简单纯函数、几十个输入 | 标准表驱动 |
| 多层状态语境、生命周期 fixture | Ginkgo |
| benchmark/fuzz/example | 标准 testing 原生能力 |
| 异步 channel/最终一致 | Gomega Eventually 很方便 |
| 只需两条断言 | 不必为层级 DSL 增加认知成本 |

NGF 同时使用两者：`cmd/gateway` 多是标准测试，controller/events 等复杂生命周期使用 Ginkgo。不要在一个小测试中同时套 `t.Run` 和多层 Ginkgo。

## 8. 并发、失败与误区

- goroutine 内直接调用 Gomega 全局断言需要 `GinkgoRecover`；更简单的方式是把值/error 发回 spec goroutine；
- Eventually 默认超时是框架配置，不应隐式承担业务 SLA；关键等待显式写上界；
- Eventually 闭包必须线程安全，读取共享变量需锁/atomic；
- BeforeEach 的包级变量仍需每例重新赋值，不能泄漏状态；
- Consistently 时间过短会产生假阴性，过长会拖慢 suite；
- 聚焦 `FIt/FDescribe` 不应提交，会跳过其他 spec；CI 可检测 focus。

## 9. 练习与检查点

1. 为什么 Reconciler 测试用 Eventually 接 eventCh？Reconcile 在 goroutine 运行且向无缓冲 channel 发送，需要异步接收推动完成。
2. DeferCleanup 为何等待 errorCh？只 cancel 不证明 EventLoop 已退出。
3. 何时用 DescribeTable？同一行为函数、仅输入/期望变化；控制流差异大则用独立 Context/It。
4. Eventually 能否替代锁？不能；轮询读取本身必须无 race。

## 源码证据索引

- 依赖：`ngf:go.mod`（Ginkgo v2.30.0、Gomega v1.41.0）。
- suite：`ngf:internal/framework/controller/controller_suite_test.go`。
- 行为树：`ngf:internal/framework/controller/reconciler_test.go`。
- Cleanup/goroutine 退出：`ngf:internal/framework/events/loop_test.go`。
- 标准测试对照：`ngf:cmd/gateway/validation_test.go`。

上一章：[[57-表驱动子测试与并行测试]] · 下一章：[[59-Counterfeiter-fake与可测试注入]]
