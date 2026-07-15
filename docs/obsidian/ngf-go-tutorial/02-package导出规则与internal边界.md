---
title: "02 package、导出规则与 internal 边界"
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

# 02 package、导出规则与 internal 边界

> [!abstract] 先建立边界感
> `package` 决定文件属于哪个编译单元；标识符首字母大小写决定跨包可见性；`internal` 目录再增加一条由 `go` 命令强制执行的导入边界。三者解决的是不同问题。

## 学习目标与前置知识

学完应能：

- 写出可被另一个包导入的函数；
- 区分包名、导入路径和目录名；
- 判断 `GetPointer`、`equalValue` 哪个能被外包调用；
- 根据 `internal` 的父目录判断谁可以导入；
- 理解 NGF 为什么把绝大部分实现放进 `internal/`。

前置：[[01-go-mod语言版本与toolchain]]。

## 语法从零开始

每个非测试 Go 文件第一条声明是 `package`：

```go
package helpers
```

同一目录中的普通 `.go` 文件必须使用相同包名，它们共同编译。测试文件可以用同包 `helpers`，也可用外部测试包 `helpers_test`。

### 导入路径与包名不是一回事

```go
import "github.com/nginx/nginx-gateway-fabric/v2/internal/framework/helpers"
```

完整字符串是导入路径；代码里默认用声明的包名 `helpers`：

```go
p := helpers.GetPointer(42)
```

如发生重名，可以显式起别名：

```go
import frameworkhelpers "example.com/project/internal/framework/helpers"
```

### 大写导出，小写包内可见

- `GetPointer`、`ReconcilerConfig`：首字母是 Unicode 大写字母，跨包可见；
- `equalValue`、`graphBuiltHealthChecker`：未导出，只能在本包引用；
- struct 字段也遵守相同规则，类型导出不代表其小写字段可访问。

> [!note] 导出不是公共稳定 API 的同义词
> 名字大写只说明编译器允许跨包访问。是否承诺兼容还取决于模块文档、版本策略和它是否位于 `internal`。

## 可独立运行的最小 demo（Go 1.26）

目录结构：

```text
packagedemo/
├── go.mod
├── main.go
└── internal/greeting/greeting.go
```

`go.mod`：

```go.mod
module example.com/packagedemo

go 1.26.0
```

`internal/greeting/greeting.go`：

```go
// 可运行示例的一部分；Go 1.26.0
package greeting

func Message(name string) string { // 导出
	return prefix + ", " + name
}

const prefix = "hello" // 仅 greeting 包可见
```

`main.go`：

```go
// 可运行示例的一部分；Go 1.26.0
package main

import (
	"fmt"

	"example.com/packagedemo/internal/greeting"
)

func main() {
	fmt.Println(greeting.Message("NGF"))
}
```

在 `packagedemo` 目录运行 `go run .`，输出 `hello, NGF`。若改成 `greeting.prefix`，编译会因未导出而失败。

### internal 规则怎么计算

导入路径含 `a/internal/b` 时，只有位于 `a` 目录树中的代码能导入它。本例允许 `example.com/packagedemo/...` 导入；另一个独立模块 `example.com/outside` 即使能看到文件也不能导入。

## 常用模式

### 1. 小写实现 + 大写窄入口

只导出真正需要的构造函数或接口，细节保持小写，减少未来兼容负担。

### 2. 外部测试包检验真实 API

`package greeting_test` 只能看导出面，适合防止测试不小心依赖内部细节。同包测试则适合验证小写辅助函数。

### 3. import alias 消除语义冲突

Kubernetes 项目常同时使用多个版本包，别名如 `corev1`、`gatewayv1` 比任意缩写更清楚。

### 4. internal 作为仓库级封装

实现可以在仓库内跨包复用，但仓库外消费者无法导入。这比“注释说不要用”更强，因为编译器会拒绝。

## NGF 生产源码实例

焦点文件：`ngf:internal/framework/helpers/helpers.go:package helpers`。

该文件声明 `package helpers`，公开 `GetPointer`、`EqualPointers`、`URLHash` 等大写函数。调用方如 `internal/controller/nginx/config/servers.go` 通过模块路径导入该包，然后调用 `helpers.GetPointer`。

边界分三层：

1. `internal/framework/helpers` 目录形成包；
2. 大写函数允许 NGF 内其他包调用；
3. 顶层 `internal/` 阻止模块外代码把这些 helper 当公共 API。

`internal/framework/helpers/helpers_test.go` 与实现相邻，验证 helper 行为。项目还在 `apis/` 放置真正面向 Kubernetes 用户的 API 类型；这与 `internal/` 的实现边界形成清楚对照。

**为何如此使用：** helpers 需要被多个内部子系统复用，但它们并非承诺给外部 Go 用户的 SDK。`internal` 让维护者可以在不承担外部兼容成本的情况下重构。这个结论由目录边界和调用范围支持。

## 可迁移与不可照搬

- 可直接迁移：默认不导出实现细节；按职责拆包；为 import 使用稳定语义别名。
- 条件迁移：用 `internal` 隐藏实现，前提是消费者都位于允许的父目录下。
- 不可照搬：不要把所有代码塞进一个巨大 `internal/common`；它会消除依赖方向而不是建立边界。
- 不要把“未导出”当安全机制；反射、生成物、进程边界等仍需单独设计。

## 失败例与排障顺序

1. `found packages x and y in the same directory`：检查同目录普通文件的 package 声明；
2. `name not exported by package`：检查标识符首字母与是否需要公开；
3. `use of internal package ... not allowed`：从 `internal` 的父目录重新计算调用方位置；
4. import cycle：包 A 与 B 互相导入，应下沉共享抽象或调整所有权，而不是起别名。

## 练习与答案

1. `internal/framework/helpers` 能否被 `cmd/gateway` 导入？能，因为两者都在仓库模块根目录树中。
2. 仓库外模块能否导入它？不能，Go 的 internal 检查会拒绝。
3. `type Config struct { logger Logger }` 即使 `Config` 导出了，外包能设置 `logger` 吗？不能，字段未导出。
4. 如何测试未导出函数？使用同包测试；若要检验公共面则使用 `_test` 外部包。

## 源码证据索引

- **源码事实**：`ngf:internal/framework/helpers/helpers.go:package helpers`。
- **源码事实**：`ngf:internal/framework/helpers/helpers.go:GetPointer`、`EqualPointers`、`URLHash`。
- **调用证据**：`ngf:internal/controller/nginx/config/servers.go:extractMirrorTargetsWithPercentages`。
- **测试佐证**：`ngf:internal/framework/helpers/helpers_test.go`。
- **边界对照**：`ngf:apis/v1alpha1/nginxgateway_types.go:NginxGateway`。

上一章：[[01-go-mod语言版本与toolchain]] · 下一章：[[03-变量声明与零值]] · 延伸：[[25-小接口与依赖注入]]、[[56-go-generate与生成代码边界]]
