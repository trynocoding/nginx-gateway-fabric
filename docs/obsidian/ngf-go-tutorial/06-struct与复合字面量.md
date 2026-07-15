---
title: "06 struct 与复合字面量"
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

# 06 struct 与复合字面量

> [!abstract]
> struct 把一组有名字、不同类型的字段组合成一个值。复合字面量负责在构造点显式填充字段；工程上优先使用带字段名的字面量，并用构造函数补充跨字段不变量。

## 学习目标与前置

- 定义 struct、读取和修改字段；
- 区分值、指针和复制语义；
- 使用命名字段复合字面量、零值、匿名 struct；
- 从 NGF `ReconcilerConfig` 看配置对象如何承载依赖与策略。

前置：[[03-变量声明与零值]]、[[05-类型定义别名与显式转换]]。

## 1. 定义与构造

```go
type Server struct {
	Name string
	Port int
	TLS  bool
}

s := Server{Name: "edge", Port: 443, TLS: true}
p := &Server{Name: "edge"}
```

未写字段得到零值。`s.Name` 读取字段，`s.Port = 8443` 修改可寻址变量的字段。

### 为什么推荐带字段名

同包内可以写 `Server{"edge", 443, true}`，但字段新增/重排会破坏调用点，也难审查各值含义。带字段名允许省略可选字段并抵抗顺序变化。跨包给导出 struct 写无键字面量也不应作为稳定模式。

### 赋值会复制 struct 值

```go
a := Server{Name: "a"}
b := a
b.Name = "b"
```

此时 `a.Name` 仍为 `a`。但若字段含 slice、map、指针或 channel，复制的只是这些引用式描述符，底层数据仍可能共享；详见 [[12-切片共享与防御性复制]]。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import "fmt"

type Config struct {
	Name    string
	Port    int
	Labels  map[string]string
	Enabled bool
}

func NewConfig(name string, port int) Config {
	return Config{
		Name:    name,
		Port:    port,
		Labels:  make(map[string]string),
		Enabled: true,
	}
}

func main() {
	cfg := NewConfig("gateway", 8080)
	copyOfCfg := cfg
	copyOfCfg.Name = "copy"
	copyOfCfg.Labels["shared"] = "yes"

	fmt.Println(cfg.Name, copyOfCfg.Name)
	fmt.Println(cfg.Labels["shared"])
}
```

```bash
gofmt -w main.go
go run main.go
# gateway copy
# yes
```

第二行证明 struct 被值复制，但 map 字段仍共享同一个底层 map。若这不是预期，复制函数必须深拷贝。

## 3. 常用模式

### 3.1 参数对象

参数多、含可选策略时，把它们组成 `Config`，调用点可读性高于一串同类型参数。

### 3.2 结果/领域值

用 struct 把相关结果绑定，让字段名表达单位与含义。若值应不可变，可不导出字段并只提供读取方法。

### 3.3 构造函数建立不变量

`NewConfig` 可检查端口范围、初始化 map/channel、填默认值。语言不会自动调用构造函数，所以是否导出字段决定调用者能否绕过它。

### 3.4 匿名 struct 用于局部表格

测试表常写 `[]struct{name string; want bool}{...}`。它适合单一局部作用域；跨函数传递时应命名，避免重复结构。

## 4. NGF：`ReconcilerConfig` 是依赖装配边界

焦点：`ngf:internal/framework/controller/reconciler.go:ReconcilerConfig`。

```go
// NGF 缩写源码，不是独立 demo
type ReconcilerConfig struct {
	Getter               Getter
	ObjectType           ngftypes.ObjectType
	EventCh              chan<- any
	NamespacedNameFilter NamespacedNameFilterFunc
	OnlyMetadata         bool
}
```

字段不是普通数据堆积，而是五种职责：读取 Kubernetes 对象、说明对象类型、输出事件、可选过滤、选择 metadata 模式。`EventCh chan<- any` 还把方向限制写进字段类型。

构造路径在 `ngf:internal/framework/controller/register.go:Register`：

```text
Register 收集 Functional Options
  → 用命名字段字面量组装 ReconcilerConfig
  → NewReconciler(cfg)
  → Reconciler 保存 cfg
  → Reconcile 在每次请求中消费这些字段
```

`NewReconciler` 返回 `&Reconciler{cfg: cfg}`，把配置按值复制进长期对象。接口、channel 和函数字段本身仍引用外部对象，因此这不是深拷贝，也没有转移资源所有权。

### 可选字段如何表现

`NamespacedNameFilter` 的零值 nil 表示不过滤；`OnlyMetadata` 的 false 表示获取完整对象。这些零值有明确语义。相反，`Getter`、`ObjectType`、`EventCh` 是运行必需依赖，但构造函数当前没有逐项 nil 校验，正确性由 `Register` 装配路径与测试保障。

`internal/framework/controller/reconciler_test.go` 通过构造 `ReconcilerConfig` 注入 fake Getter 和 event channel，覆盖 upsert、delete、过滤和错误路径。这是参数 struct 改善测试注入的直接收益。

## 5. 设计取舍与迁移边界

- **直接复用**：命名字段字面量；把相关依赖组成配置类型；用字段类型表达方向。
- **条件复用**：将 Config 按值保存，前提是清楚内部 map/slice/指针是否共享。
- **不可照搬**：对外公共 Config 任意增加导出字段而不考虑兼容；或假定 `NewXxx` 会被语言强制调用。
- 若必需字段可能来自不可信调用者，应在构造函数校验并返回 error；不要等到运行热路径 nil panic。

## 6. 常见误区

- `new(Server)` 只得到零值 `*Server`，不会运行 `NewServer`；
- `&Server{}` 可能逃逸到堆，也可能不逃逸，语义上不要依赖具体分配位置；
- 比较 struct 需要所有字段都可比较；含 map/slice 的 struct 不能用 `==`；
- 值复制不等于深复制；引用式字段是最常见陷阱；
- 空 struct `struct{}` 是零字段类型，常作信号或集合占位，见 [[14-map空struct集合模式]]。

## 7. 练习与答案

1. 给 Config 新增 `Timeout time.Duration`，命名字段字面量会怎样？旧调用仍编译，新字段取零值。
2. 为什么复制含 map 的 Config 后修改 map 会相互影响？复制的是 map header，二者指向同一运行时 map。
3. `NamespacedNameFilter == nil` 有何语义？Reconcile 跳过过滤步骤，处理所有请求。
4. 如何强化必需依赖？使用未导出配置/字段或让 `NewReconciler` 校验并返回 `(*Reconciler, error)`，同时更新 Register 和测试。

## 源码证据索引

- `ngf:internal/framework/controller/reconciler.go:ReconcilerConfig`、`Reconciler`、`NewReconciler`。
- `ngf:internal/framework/controller/register.go:Register`（配置字面量构造点）。
- `ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`（字段消费者）。
- `ngf:internal/framework/controller/reconciler_test.go`（注入与行为测试）。

上一章：[[05-类型定义别名与显式转换]] · 下一章：[[07-struct-tag与JSON字段语义]] · 延伸：[[25-小接口与依赖注入]]、[[28-构造函数与不变量]]
