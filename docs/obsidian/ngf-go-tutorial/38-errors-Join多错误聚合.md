---
title: "38 errors.Join 与多错误聚合"
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

# 38 `errors.Join` 与多错误聚合

> [!abstract]
> `errors.Join` 把多个独立失败保存在一棵错误树中，而不是只留下“最后一个错误”。nil 子项会被忽略；所有子项都为 nil 时结果为 nil。`errors.Is`/`As` 会遍历整棵树，但 `errors.Unwrap` 只处理单子节点接口，不能用它展开 Join。

## 学习目标与前置

- 理解 `Unwrap() []error` 与 `Unwrap() error` 的区别；
- 掌握 Join 的 nil、单项、多项语义；
- 正确用 Is/As 判断树中任意分支；
- 判断什么时候应 fail-fast、什么时候应聚合全部失败。

前置：[[36-错误链与百分号w]]、[[37-errors-Is-As与自定义错误]]。

## 1. 从链到树

传统包装节点实现：

```go
interface{ Unwrap() error }
```

Join 节点实现：

```go
interface{ Unwrap() []error }
```

因此错误结构可以混合：Join 的每个子错误可能又有 `%w` 单链，或继续是另一个 Join。标准库 `errors.Is`/`As` 对两种接口都做深度优先遍历。

> [!warning]
> `errors.Unwrap(joined)` 返回 nil，因为这个便利函数只调用 `Unwrap() error`，不会调用 `Unwrap() []error`。检查 Join 子项需做接口断言，日常分类应直接用 `errors.Is/As`。

## 2. nil 和单项语义

```go
errors.Join(nil, nil) // nil
errors.Join(err, nil) // 非 nil，语义上包含 err
```

不要依赖 `errors.Join(err) == err`；调用者应使用 `errors.Is(joined, err)`。`Error()` 文本用于展示，多项通常以换行连接，不应作为机器解析协议。

## 3. 可独立运行的最小 demo

**可运行 demo（Go 1.26.0，保存为 `main.go`）：**

```go
package main

import (
	"errors"
	"fmt"
)

var (
	ErrControl = errors.New("control logger rejected level")
	ErrData    = errors.New("data logger rejected level")
)

type ComponentError struct {
	Name string
	Err  error
}

func (e *ComponentError) Error() string {
	return fmt.Sprintf("%s: %v", e.Name, e.Err)
}

func (e *ComponentError) Unwrap() error { return e.Err }

func setAll() error {
	return errors.Join(
		&ComponentError{Name: "control", Err: ErrControl},
		nil,
		&ComponentError{Name: "data", Err: ErrData},
	)
}

func main() {
	err := setAll()
	fmt.Println(errors.Is(err, ErrData))
	var ce *ComponentError
	fmt.Println(errors.As(err, &ce), ce.Name)
	fmt.Println(errors.Join(nil, nil) == nil)
}
```

验证：

```bash
gofmt -w main.go
go run main.go
# true
# true control
# true
```

`As` 返回第一个深度优先匹配，因此得到 control。若要收集所有 typed error，需要显式遍历树。

## 4. 显式遍历所有节点

**说明性片段（展示算法，不是本章 demo 的必需部分）：**

```go
func walk(err error, visit func(error)) {
	if err == nil {
		return
	}
	visit(err)
	switch e := err.(type) {
	case interface{ Unwrap() []error }:
		for _, child := range e.Unwrap() {
			walk(child, visit)
		}
	case interface{ Unwrap() error }:
		walk(e.Unwrap(), visit)
	}
}
```

遍历顺序是当前节点在前、子项按 Join 输入顺序深度优先。不要修改 `Unwrap()` 返回的 slice；标准约定要求调用者只读。

## 5. 常用聚合模式

### 5.1 fan-out 配置

同一个日志级别要应用到多个 logger，每个 setter 相互独立，应全部尝试后返回聚合错误。

### 5.2 批量清理

删除多个资源时，一个失败不应阻止其他清理，收集所有错误便于重试和诊断。

### 5.3 主操作 + defer 清理

写文件失败和 Close 失败都重要，可把主体 `resultErr` 与清理错误 Join。

### 5.4 并发 fan-in

多个 goroutine 返回错误时可聚合，但要先安全收集；Join 本身不提供并发同步，也不定义取消策略。

## 6. NGF：日志级别 fan-out

**NGF 缩写源码（不是独立 demo）：**

```go
func (m multiLogLevelSetter) SetLevel(level string) error {
	allErrs := make([]error, 0, len(m.setters))
	for _, s := range m.setters {
		if err := s.SetLevel(level); err != nil {
			allErrs = append(allErrs, err)
		}
	}
	return errors.Join(allErrs...)
}
```

调用关系：control-plane 配置变化 → multi setter 依次调用所有 logger setter → 每个 setter 独立解析/设置 → 收集失败 → 返回一棵错误树。没有错误时 `allErrs` 为空，`Join` 返回 nil，所以成功路径自然满足 error-last 约定。

`internal/controller/log_level_setters_test.go:TestMultiLogLevelSetter_SetLevel` 先验证三个 setter 都被调用；再让三个都失败，构造同顺序 Join 作为期望。这证明策略是“尽力全部应用”，不是第一个失败就停止。

其他生产实例包括：

- `internal/framework/file/file.go:Write` 聚合主体与 Close 错误；
- `internal/controller/provisioner/handler.go:provisionResourceForAllGateways` 聚合各 Gateway 失败；
- `internal/controller/handler.go` 合并 config 与 upstream 更新错误。

## 7. 边界、误区与策略

- 有依赖顺序的步骤不应盲目 Join：前置失败后继续可能造成破坏，应 fail-fast 或补偿。
- Join 不会自动添加“哪个组件”语境；收集前先 `%w` 或 typed error 标注来源。
- `err != nil` 只能知道至少一项失败；分类用 Is/As。
- 不要把同一错误重复加入，除非确实代表两个失败事件。
- 聚合会允许部分成功，调用者必须知道是否需要回滚、重试全部还是只重试失败项。

迁移边界：若日志配置要求原子一致性，当前 Join fan-out 不够，需要预校验、事务式应用或回滚；仅改变错误返回无法消除部分成功状态。

## 8. 练习与答案

1. 给 demo 两个子错误各包一层 `%w`，确认 Is 仍为 true。
2. 使用 `walk` 收集所有 `*ComponentError` 名称。
3. 什么时候 `return errors.Join(errs...)` 可以替代循环中的立即 return？

答案检查点：只有各操作相互独立、继续执行安全且调用者接受部分成功时才聚合。若 B 依赖 A 的成功，A 失败后应停止或进入明确补偿路径。

## 源码证据索引

| 主题 | 证据 |
|---|---|
| fan-out 聚合 | `ngf:internal/controller/log_level_setters.go:multiLogLevelSetter.SetLevel` |
| 全调用/全失败测试 | `ngf:internal/controller/log_level_setters_test.go:TestMultiLogLevelSetter_SetLevel` |
| 主体 + Close | `ngf:internal/framework/file/file.go:Write` |
| 多 Gateway 聚合 | `ngf:internal/controller/provisioner/handler.go:provisionResourceForAllGateways` |

下一步：[[39-panic与不变量保护]]、[[47-WaitGroup与fan-out-fan-in]]。
