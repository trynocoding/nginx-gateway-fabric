---
title: "09 Go 1.26 的 new(expr) 与项目 GetPointer 模式"
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

# 09 Go 1.26 的 new(expr) 与项目 GetPointer 模式

> [!abstract]
> Go 1.26 扩展了 `new`：`new(T)` 仍返回指向 T 零值的指针；`new(expr)` 返回指向表达式求值结果的指针。NGF 的 `GetPointer[T](v)` 在旧写法上实现相同“值转指针”目的，并在当前代码中仍广泛使用。

## 学习目标与前置

- 区分 `new(T)`、Go 1.26 `new(expr)`、`&variable`、`&T{}`；
- 知道返回局部值地址为何安全；
- 用类型推断或显式类型实参构造 API 指针；
- 判断新代码何时用内建 `new(expr)`，何时保持项目 helper 一致性。

前置：[[08-指针nil与可选字段]]、[[01-go-mod语言版本与toolchain]]。

## 1. 四种取指针方式

```go
var n int
p1 := &n            // 已有可寻址变量
p2 := new(int)      // *int，指向零值 0
p3 := new(42)       // Go 1.26：*int，指向值 42
p4 := &Config{Port: 8080} // 复合字面量的地址
```

`new` 返回新变量的地址，不是“构造函数”。`new(Config)` 不会调用 `NewConfig`，只得到所有字段为零值的 `*Config`。

### `new(expr)` 的求值规则

表达式先求值，新变量类型取表达式类型、初值取结果。无类型常量先转为默认类型，所以 `new(42)` 是 `*int`；可写 `new(int32(42))` 得 `*int32`。预声明 `nil` 不能单独作为参数，因为没有足够类型信息。

```go
calls := 0
p := new(func() int { calls++; return calls }())
```

表达式只在这里求值一次，`*p == 1`。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；要求 Go 1.26.0
package main

import "fmt"

type Port int32

func Pointer[T any](v T) *T { return &v }

func main() {
	zero := new(Port)
	fromExpr := new(Port(8080))
	fromHelper := Pointer(Port(8443))

	fmt.Printf("%T=%d %T=%d %T=%d\n",
		zero, *zero, fromExpr, *fromExpr, fromHelper, *fromHelper)
}
```

```bash
gofmt -w main.go
go run main.go
# *main.Port=0 *main.Port=8080 *main.Port=8443
```

失败实验：在语言版本低于 1.26 的模块中编译 `new(Port(8080))`，会被拒绝；`Pointer(Port(8080))` 则是此前版本可用的普通泛型函数。

## 3. 常用模式与选择表

| 需求 | 推荐 | 说明 |
|---|---|---|
| 已有变量并希望共享修改 | `&v` | 指向原变量 |
| 需要 T 的零值指针 | `new(T)` | 不运行构造逻辑 |
| 临时表达式转指针（Go 1.26） | `new(expr)` | 简短、内建 |
| 旧版本/项目统一 helper | `Pointer(expr)` | 泛型辅助函数 |
| struct 具名初始化 | `&T{Field: value}` | 字段最清楚 |

### 显式目标类型

```go
p := new(gatewayv1.PortNumber(8443))
q := helpers.GetPointer[gatewayv1.PortNumber](8443)
```

两者都得到 `*gatewayv1.PortNumber`。helper 的显式类型实参还能让无类型常量直接按目标类型实例化。

## 4. NGF：`GetPointer` 的定义与生产调用

焦点：`ngf:internal/framework/helpers/helpers.go:GetPointer`。

```go
// NGF 原样短源码，不是独立 demo
func GetPointer[T any](v T) *T {
	return &v
}
```

形参 `v` 是调用值的副本，返回其地址在 Go 中安全；若它逃逸，编译器确保生命周期足够长。修改调用前的原变量不会自动修改 `*p`。

一个代表性生产调用在 `ngf:internal/controller/handler.go:getGatewayAddressesForStatus`：

```go
Type: helpers.GetPointer(gatewayv1.IPAddressType),
```

数据关系：Service 地址被转换为 Gateway status address，`Type` 是可选指针；编译器推断 `T` 为 `gatewayv1.AddressType` 对应的命名类型，helper 返回正确指针，避免只为取地址声明临时变量。

另一处 `internal/controller/nginx/config/servers.go:extractMirrorTargetsWithPercentages` 用 `helpers.GetPointer(100.0)` 表达“未指定镜像百分比时显式采用 100”。这体现 helper 服务多种类型，而不是某一 API 专用构造器。

## 5. Go 1.26 后是否应删除 helper

当前 revision 仍有大量生产调用，统一替换会形成较大机械 diff，且不是功能必需。新代码可按项目约定选择：

- 若最低语言版本确定是 1.26，`new(expr)` 更直接；
- 修改邻近既有代码时保持 `helpers.GetPointer` 可减少风格混杂；
- 不要为了展示新语法无目的地全仓替换；先确认 lint、贡献指南和维护者偏好。

这是迁移建议，不是从源码推导出的官方弃用计划；当前 helper 没有 deprecated 标记。

## 6. 边界与误区

- `new(T)` 初始化零值，`new(expr)` 初始化表达式值，不能混为一谈；
- `new(nil)` 无法确定类型且不合法；若需指向 nil 接口值，可 `new(error(nil))` 或 helper 显式指定类型；
- `GetPointer(v)` 指向副本，不适合期望别名到原变量的场景；
- 指针能表达可选性，但默认化/校验仍由业务层负责；
- 不要依据源码写法断言对象一定在堆上；分配位置是编译器实现选择。

## 7. 练习与答案

1. `new(123)` 返回什么类型和值？`*int`，指向 123。
2. `new(int)` 呢？`*int`，指向 0。
3. `x := 1; p := GetPointer(x); x = 2` 后 `*p` 是多少？1，因为 helper 接收副本。
4. 新项目最低 Go 1.25，能用 `new(expr)` 吗？不能，应使用临时变量或泛型 Pointer helper。

## 验证与源码证据索引

- **本地语言规范**：Go 1.26 spec `Allocation` 明确 `new` 参数可为类型或表达式。
- `ngf:internal/framework/helpers/helpers.go:GetPointer`。
- `ngf:internal/controller/handler.go:getGatewayAddressesForStatus`。
- `ngf:internal/controller/nginx/config/servers.go:extractMirrorTargetsWithPercentages`。
- `ngf:internal/framework/helpers/helpers_test.go` 及使用 GetPointer 的 API 转换测试。

上一章：[[08-指针nil与可选字段]] · 下一章：[[10-数组与切片的类型差异]] · 延伸：[[29-泛型函数与类型推断]]
