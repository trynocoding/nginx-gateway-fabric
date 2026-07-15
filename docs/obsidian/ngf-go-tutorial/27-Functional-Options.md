---
title: "27 Functional Options"
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

# 27 Functional Options

> [!abstract] 核心结论
> Functional Options 把可选配置表示为修改私有 config 的函数。可靠顺序是“建立默认值 → 顺序应用 options → 集中校验 → 构造对象”。Option 工厂负责表达单个意图，最终构造入口负责跨字段不变量；必须用测试固定默认值、覆盖顺序和失败配置。

## 学习目标与前置

前置：[[18-可变参数]]、[[19-函数值闭包与高阶函数]]、[[25-小接口与依赖注入]]。完成后应能：

- 从零实现 `type Option func(*config)`；
- 区分默认值、单 option 校验与跨 option 校验；
- 说明“后传入者覆盖前者”或其他明确的冲突规则；
- 读懂 NGF controller `Register` 的 default/apply/consume 路径及 OnlyMetadata 不变量。

## 1. 模式由三块组成

```go
type config struct { /* 私有字段 */ }
type Option func(*config)

func WithX(x X) Option {
	return func(cfg *config) { cfg.x = x }
}
```

构造入口接收 `options ...Option`。配置保持私有，调用者只能通过公开 option 表达变化；添加新 option 不破坏既有调用。但这不是“免费兼容”：默认值和 option 交互仍是 API 契约。

## 2. 可独立运行 demo：默认值、校验、不变量

**可运行示例（Go 1.26.0，标准库）：**

```go
package main

import (
	"errors"
	"fmt"
	"time"
)

type Server struct {
	address string
	timeout time.Duration
}

type config struct {
	host    string
	port    int
	timeout time.Duration
}

type Option func(*config) error

func WithPort(port int) Option {
	return func(cfg *config) error {
		if port < 1 || port > 65535 {
			return errors.New("port out of range")
		}
		cfg.port = port
		return nil
	}
}

func WithTimeout(timeout time.Duration) Option {
	return func(cfg *config) error {
		cfg.timeout = timeout
		return nil
	}
}

func NewServer(options ...Option) (*Server, error) {
	cfg := config{host: "127.0.0.1", port: 8080, timeout: time.Second}
	for _, option := range options {
		if option == nil {
			return nil, errors.New("nil option")
		}
		if err := option(&cfg); err != nil {
			return nil, fmt.Errorf("apply option: %w", err)
		}
	}
	if cfg.timeout <= 0 {
		return nil, errors.New("timeout must be positive")
	}
	return &Server{
		address: fmt.Sprintf("%s:%d", cfg.host, cfg.port),
		timeout: cfg.timeout,
	}, nil
}

func main() {
	server, err := NewServer(WithPort(9000), WithPort(9001))
	fmt.Println(server.address, server.timeout, err)
	_, err = NewServer(WithTimeout(0))
	fmt.Println(err)
}
```

预期第一行含 `127.0.0.1:9001 1s <nil>`，证明按顺序、last wins；第二行是 timeout 校验错误。已在 `go1.26.0` 验证成功和失败路径。

## 3. 默认值、校验与不变量如何分工

### 默认值

默认值必须在应用 option 前一次性建立。零值可用时也要刻意决定是使用零值，还是用非零安全默认。默认值变化会改变所有未传 option 的调用者，应当视作行为变更。

### 单字段校验

像端口范围，可在 `WithPort` 内尽早拒绝，因此可令 `Option func(*config) error`。另一种做法是 option 只赋值，统一在最后校验；API 更简单，但错误离来源更远。

### 跨字段不变量

例如 TLS 开启时 cert/key 必须成对，单个 option 无法独立判断最终状态。应在所有 option 应用完成后集中验证，避免 option 顺序改变“暂时非法”的中间态。

### 构造后封装

config 可以只存在于构造阶段；最终对象只保存规范化后的字段，防止运行时重新进入非法组合。

## 4. 四种常用 option 语义

| 语义 | 示例 | 冲突规则 |
|---|---|---|
| 覆盖型 | `WithTimeout` | 通常 last wins |
| 开关型 | `WithOnlyMetadata()` | 出现即 true |
| 累加型 | `WithMiddleware(m...)` | 明确 append 顺序 |
| 注入型 | `WithNewReconciler(fake)` | 替换构造依赖，多用于测试 |

累加 option 接收 slice/map 时要决定是否防御性复制；否则调用者构造后修改容器会改变对象。nil option 若不检查，`opt(&cfg)` 会 panic。

## 5. NGF 生产实例：controller `Register`

`internal/framework/controller/register.go` 的核心结构：

```go
type Option func(*config)

func defaultConfig() config {
	return config{newReconciler: NewReconciler}
}
```

`Register(..., options ...Option)` 先 `cfg := defaultConfig()`，再按传入顺序 `opt(&cfg)`。随后不同字段进入各自消费点：

| option | config 字段 | 运行效果 |
|---|---|---|
| `WithNamespacedNameFilter` | `namespacedNameFilter` | 写入 ReconcilerConfig，运行时过滤 key |
| `WithK8sPredicate` | `k8sPredicate` | builder 注册 event filter |
| `WithFieldIndices` | `fieldIndices` | 完成 controller 前调用 `AddIndex` |
| `WithNewReconciler` | `newReconciler` | 替换构造函数，主要便于单测 |
| `WithOnlyMetadata` | `onlyMetadata` | 使用 builder.OnlyMetadata，并传播给 Reconciler |

默认值中只有 `newReconciler: NewReconciler` 必须非 nil，否则最后调用会 panic。其他零值表示“不启用”。

## 6. NGF 的校验和失败边界

NGF 的 `Option` 不返回 error，`WithX` 也不做输入校验。最终 `Register` 在消费配置时处理失败：

- Field index 失败：`AddIndex` 返回包装 error，停止注册；
- OnlyMetadata 但 object 没有 GVK：显式 panic；
- controller builder Complete 失败：返回包装 error；
- nil option：当前实现调用时 panic；
- `WithNewReconciler(nil)`：直到构造 reconciler 时 panic。

`WithOnlyMetadata` 注释还规定：开启后必须用 `PartialObjectMetadata` 进行 Get/List，不能把缓存中的 metadata-only 对象当完整 Pod 等类型。这是框架集成边界，不只是 bool 开关。

> [!warning] 迁移时不要机械复制 panic 策略
> NGF 将缺 GVK 视为内部 wiring 错误。面向最终用户配置的库通常应返回 error，避免单个配置让进程崩溃。

## 7. 如何测试 Options

至少固定四组契约：

1. **默认值**：零 options 得到预期默认构造器/超时；
2. **单 option**：每个 option 只修改目标字段；
3. **组合与顺序**：重复覆盖是 first wins、last wins 还是 error；
4. **失败不变量**：非法范围、互斥字段、nil option、外部 builder 失败。

`internal/framework/controller/register_test.go:TestRegister` 传入全部 options，并通过 fake manager/indexer 与注入的 `newReconciler` 观察最终配置；覆盖索引失败、builder 失败以及 OnlyMetadata 缺 GVK panic。它证明组合消费路径，但没有独立锁定“重复 option 的覆盖顺序”和 nil option；若这些成为公共依赖，应补专门测试。

## 8. 何时不用 Functional Options

- 只有一两个必填参数：直接参数更清楚；
- 配置本身要序列化/比较/复用：公开 Config struct 可能更自然；
- option 之间形成复杂状态机：builder 或显式校验模型更容易理解；
- 需要在运行时修改：Functional Options 通常是构造期模式，不是动态配置系统。

## 9. 练习与检查点

1. 为 demo 写表驱动测试：默认值、last wins、非法 port、零 timeout、nil option。检查每个不变量只有一个明确错误出口。
2. 新增 `WithHost`，拒绝空字符串。判断校验应放 option 还是集中 validate；写下理由。
3. 给 NGF `Register` 设计非破坏性的 nil option 防护。检查 API 选择是返回 error 还是保持 panic，并评估现有调用方。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| Option/config/default | `internal/framework/controller/register.go:Option`、`config`、`defaultConfig` |
| 顺序应用与消费 | `internal/framework/controller/register.go:Register` |
| timeout 清理 | `internal/framework/controller/register.go:AddIndex` |
| 默认/组合/失败测试 | `internal/framework/controller/register_test.go:TestRegister` |

上一章：[[26-类型断言与type-switch]] · 下一章：[[28-构造函数与不变量]] · 可变参数基础：[[18-可变参数]]
