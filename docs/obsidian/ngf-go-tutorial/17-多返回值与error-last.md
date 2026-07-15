---
title: "17 多返回值与 error-last 约定"
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

# 17 多返回值与 error-last 约定

> [!abstract] 核心结论
> Go 的多返回值不是一个运行时 tuple 对象，而是函数签名中的多个结果位置。把 `error` 放在最后，可以让调用者先接收业务结果、再立即检查失败；失败时，前面的结果必须被当作不可用，除非函数文档明确声明“部分结果仍有效”。

## 学习目标与前置

前置：[[16-for-range整数range与迭代]]、会声明函数和理解 `error` 接口。完成后应能：

- 写出普通、命名、多返回值函数，并用 `_` 忽略不需要的结果；
- 区分“返回零值 + error”和“部分结果 + error”的契约；
- 读懂 NGF 的 `parseS3URI` 为什么返回三个结果，以及调用者为什么先判错；
- 判断何时应返回 struct，而不是不断增加返回值。

本章不展开错误链；`%w`、`errors.Is/As` 见 [[36-错误链与百分号w]] 与 [[37-errors-Is-As与自定义错误]]。

## 1. 从语法开始：结果是签名的一部分

```go
func split(s string) (string, string, error)
```

调用时必须按位置接收：

```go
left, right, err := split("a:b")
_, right, err := split("a:b") // 用空标识符忽略 left
```

不能只接一个结果，也不能把它当成单个 tuple 传递。另一个函数如果签名完全匹配，可直接转交全部结果：

```go
func wrapped(s string) (string, string, error) {
	return split(s)
}
```

### 命名结果与裸 return

`func f() (value string, err error)` 在函数入口就创建了两个零值变量。命名结果适合解释多个同类型结果，或供 deferred closure 修改；但长函数里的裸 `return` 会隐藏返回了谁。团队代码更常见的折中是：结果命名用于文档，返回点仍显式写值。

## 2. 可独立运行的最小 demo

**可运行示例（Go 1.26.0，标准库，无外部依赖）：**

```go
package main

import (
	"errors"
	"fmt"
	"strings"
)

func splitPair(input string) (left, right string, err error) {
	left, right, ok := strings.Cut(input, ":")
	if !ok || left == "" || right == "" {
		return "", "", errors.New("want non-empty left:right")
	}
	return left, right, nil
}

func main() {
	for _, input := range []string{"blue:8080", "broken"} {
		left, right, err := splitPair(input)
		if err != nil {
			fmt.Printf("%q: %v\n", input, err)
			continue
		}
		fmt.Printf("left=%s right=%s\n", left, right)
	}
}
```

运行：`go run main.go`。预期先输出 `left=blue right=8080`，再输出包含 `want non-empty left:right` 的错误。该 demo 已用本仓库环境的 `go1.26.0` 执行验证。

## 3. 四种常用模式

### 模式一：业务值 + error

`value, err := load()` 是最常见契约。调用者应把 `if err != nil` 放在尽量靠近调用的位置；不要先消费 `value` 再判错。

### 模式二：值 + bool（查找而非异常）

map、类型断言和 `strings.Cut` 常返回 `(value, ok)`。缺失是正常分支时，`bool` 比构造 error 更清楚：

```go
value, ok := cache[key]
```

### 模式三：多个同类结果 + 命名

`(bucket, key string, err error)` 比 `(string, string, error)` 更能解释位置含义。命名不代表必须裸返回。

### 模式四：部分成功

解析器有时返回“已解析部分 + error”。这种契约必须写进注释，调用方也要明确是否能使用部分结果。默认心智模型应是：`err != nil` 时其他结果无效。

## 4. NGF 生产实例：`parseS3URI`

**源码节选（省略重复错误文本，不是可独立运行示例）：**

```go
func parseS3URI(uri string) (bucket, key string, err error) {
	// 校验 scheme、bucket 与 key
	bucket = path[:slashIdx]
	key = path[slashIdx+1:]
	return bucket, key, nil
}
```

证据位置：`internal/framework/waf/fetch/s3/s3.go:parseS3URI`。它把一个 S3 URI 拆成两个同为 `string` 的业务结果，命名结果避免调用者记错位置。每个失败分支都返回 `"", "", error`，所以它没有“部分结果可用”的隐含契约。

调用者 `(*Fetcher).FetchBundle` 的关键顺序是：

1. `bucket, key, err := parseS3URI(location)`；
2. `err != nil` 时用 `%w` 增加 `invalid S3 location` 上下文并返回；
3. 只有成功后才构建 S3 client 和 `GetObjectInput`。

这条边界很重要：错误 URI 不应触发网络访问。`internal/framework/waf/fetch/s3/s3_test.go` 对空 URI、错误 scheme、缺 bucket/key 与成功拆分进行表驱动验证。

## 5. 边界、误区与迁移判断

> [!warning] 不要把零值当成错误信号
> `""` 或 `0` 可能是合法业务值。需要解释失败原因时返回 `error`；只有“是否存在”这种正常二分状态才优先 `(T, bool)`。

- 返回值超过三四个且总是一起流动时，定义结果 struct 会更易扩展；
- 命名结果变量会被闭包捕获，尤其要小心 `defer` 修改它；
- `value, _ := f()` 会丢失失败信息，只适合错误已被证明不可能或已在别处处理的场景；
- error-last 是约定而非编译器规则，但标准库与工具链都围绕这一约定形成可读性预期。

**可直接迁移：** error-last、就地判错、失败时不消费结果。**有条件迁移：** 部分结果，必须文档化并测试。**不建议复制：** 用特殊零值编码错误。

## 6. 练习与检查点

1. 把 demo 改为 `(Pair, error)`，其中 `Pair` 含 `Left/Right`。检查：调用点不再依赖两个 string 的位置。
2. 为 `splitPair(":8080")` 加失败用例。检查：两个字符串均为空，error 非 nil。
3. 思考 `parseS3URI` 是否应返回 `url.URL`。答案检查：它只需要 bucket/key，返回更大的通用类型会扩大契约；除非后续要保留 query/escaping 语义，否则当前小结果更直接。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| 多命名结果与失败零值 | `internal/framework/waf/fetch/s3/s3.go:parseS3URI` |
| 调用方先判错 | `internal/framework/waf/fetch/s3/s3.go:(*Fetcher).FetchBundle` |
| URI 正反例 | `internal/framework/waf/fetch/s3/s3_test.go` |

上一章：[[16-for-range整数range与迭代]] · 下一章：[[18-可变参数]] · 错误深化：[[36-错误链与百分号w]]
