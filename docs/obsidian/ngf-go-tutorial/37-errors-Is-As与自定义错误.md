---
title: "37 errors.Is、errors.As 与自定义错误类型"
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

# 37 `errors.Is`、`errors.As` 与自定义错误类型

> [!abstract]
> `Is` 问“这条错误树中是否具有目标语义”，`As` 问“能否找到可赋给目标类型的错误”。前者常配哨兵，后者常配带字段的自定义类型；两者都会沿 `Unwrap() error` 或 `Unwrap() []error` 深度优先遍历。

## 学习目标与前置

- 掌握 `Is` 的相等、`Is(error) bool` 定制和遍历语义；
- 正确写 `var target *MyError; errors.As(err, &target)`；
- 实现带 `Error`/`Unwrap` 的结构化错误；
- 读懂 NGF `nonTransientError` 如何控制重试。

前置：[[36-错误链与百分号w]]。

## 1. `Is`：判断语义，不比较文本

概念上，`errors.Is(err, target)` 对当前节点及其子节点检查：

1. 当前错误是否等于 target（可比较时）；
2. 当前错误是否实现 `Is(error) bool` 且返回 true；
3. 否则沿 `Unwrap` 继续。

自定义 `Is` 方法应做浅比较，不应再次调用 `Unwrap`，遍历由标准库负责。

```go
if errors.Is(err, context.Canceled) {
	return
}
```

这比字符串包含 `"canceled"` 稳定，也能穿过 `%w` 包装。

## 2. `As`：按可赋值类型提取

```go
var pe *ParseError
if errors.As(err, &pe) {
	fmt.Println(pe.Line)
}
```

第二个参数必须是非 nil 指针，通常是“指向目标类型变量的指针”。若错误类型的方法使用指针接收者，目标通常写 `**ParseError` 的效果，即语法上的 `&pe`。

`As` 不只做精确类型相等，而是找可赋值给目标的节点；错误还可实现自定义 `As(any) bool`，但这类适配应少用并清楚记录。

## 3. 可独立运行的最小 demo

**可运行 demo（Go 1.26.0，保存为 `main.go`）：**

```go
package main

import (
	"errors"
	"fmt"
)

var ErrInvalid = errors.New("invalid input")

type FieldError struct {
	Field string
	Err   error
}

func (e *FieldError) Error() string {
	return fmt.Sprintf("field %s: %v", e.Field, e.Err)
}

func (e *FieldError) Unwrap() error { return e.Err }

func validate() error {
	return fmt.Errorf("create route: %w", &FieldError{
		Field: "hostname",
		Err:   ErrInvalid,
	})
}

func main() {
	err := validate()
	fmt.Println(errors.Is(err, ErrInvalid))
	var fe *FieldError
	if errors.As(err, &fe) {
		fmt.Println(fe.Field)
	}
}
```

验证：

```bash
gofmt -w main.go
go run main.go
# true
# hostname
```

同一条链同时支持：Is 找根因语义，As 取中间层结构。

## 4. 常用模式

### 4.1 哨兵错误 + `Is`

适合调用者只需做有限分支，如 canceled、not found、conflict。哨兵一旦导出就是兼容性合同。

### 4.2 结构化错误 + `As`

适合调用者需要 Path、StatusCode、RetryAfter 等数据。不要要求调用者解析 `Error()` 字符串。

### 4.3 包装 + 双重判断

自定义错误实现 Unwrap 后，上层既可 `As` 获取上下文，也可 `Is` 判断底层系统错误。

### 4.4 自定义 `Is`

适合目标是一个“模板错误”时做字段匹配，但方法只能比较目标暴露的浅层语义；复杂策略通常用普通函数更易懂。

## 5. NGF：`nonTransientError` 控制重试

**NGF 缩写源码（不是独立 demo）：**

```go
type nonTransientError struct {
	err error
}

func (e *nonTransientError) Error() string { return e.err.Error() }
func (e *nonTransientError) Unwrap() error { return e.err }
```

`HTTPFetcher.fetch` 的重试回调收到 `fetchErr` 后：

```go
var nte *nonTransientError
if errors.As(fetchErr, &nte) {
	return false, fetchErr
}
```

调用/控制关系：HTTP/N1C 分支识别 4xx、编译失败、校验失败等不可重试原因 → 包成 `*nonTransientError` → 中间层可继续 `%w` 补语境 → `errors.As` 穿透包装找到分类节点 → 立即终止指数退避。普通网络/5xx 错误则保存为 `lastErr` 并重试。

这里选自定义类型 + As，而不是一个哨兵，因为需要把原始具体错误一并保存和展示；也不通过字符串判断“non-transient”。`internal/framework/waf/fetch/fetch_test.go` 中 N1C compilation failed 用 `RetryAttempts: 3` 并验证失败结果，相关 HTTP 状态测试验证不可重试分支。

另一个 `Is` 生产例在 `internal/controller/status/updater.go:writeStatuses`：指数退避返回错误后，`errors.Is(err, context.Canceled)` 会让取消静默退出，其他错误才记录日志。

## 6. 精确语义与误区

- `errors.Is(nil, nil)` 为 true；`errors.As(nil, target)` 为 false。
- `Is` 不是比较 `Error()` 文本。
- `As(err, &value)` 的 target 必须是非 nil 指针，否则 panic；让编译器/vet 检查常见误用。
- 遍历是前序、深度优先；在 Join 树中若多个节点都可赋值，As 返回第一个匹配。
- 自定义 `Is` 不应递归调用 `errors.Is(e.Err, target)`，否则职责重复且可能产生意外遍历。
- 只为了日志不需要 As；结构化日志可以直接记录 err，分类逻辑才需要 Is/As。

## 7. 策略与迁移边界

| 需求 | 选择 |
|---|---|
| 只需稳定类别 | 哨兵 + Is |
| 需要字段 | 自定义类型 + As |
| 同时保留根因 | 自定义类型实现 Unwrap |
| 多个独立原因 | Join，Is/As 仍遍历 |
| 内部不变量 | panic，而非伪造错误类别 |

若“是否重试”未来需要 RetryAfter、最大次数等数据，可把 `nonTransientError` 演进为更一般的 typed retry error；但必须同步 fetch loop 和测试。若只有 transient/non-transient 二分，当前私有 marker 类型足够。

## 8. 练习与答案

1. 在 demo 外再包两层 `%w`，确认 Is/As 不变。
2. 把 `FieldError.Unwrap` 删除，分别观察 Is 和 As。
3. 写错误树含两个 FieldError，As 会返回哪一个？

答案：删除 Unwrap 后，As 仍能找到外层 FieldError，但 Is 无法到达其 `ErrInvalid`；Join 场景按传入子错误顺序做深度优先前序遍历，返回首个可赋值节点，业务逻辑不应依赖模糊的“任意一个”。

## 源码证据索引

| 主题 | 证据 |
|---|---|
| typed marker 与 Unwrap | `ngf:internal/framework/waf/fetch/fetch.go:nonTransientError` |
| As 控制退避 | `ngf:internal/framework/waf/fetch/fetch.go:HTTPFetcher.fetch,pollN1CCompileStatus` |
| 不可重试测试 | `ngf:internal/framework/waf/fetch/fetch_test.go`（N1C compilation failed / 4xx cases） |
| Is 识别取消 | `ngf:internal/controller/status/updater.go:Updater.writeStatuses`；`internal/controller/status/updater_test.go` |

下一步：[[38-errors-Join多错误聚合]]、[[44-context传递与取消]]。
