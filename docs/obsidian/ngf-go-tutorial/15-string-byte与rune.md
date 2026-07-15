---
title: "15 string、[]byte 与 rune"
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

# 15 string、[]byte 与 rune

> [!abstract]
> Go string 是不可变字节序列，通常承载 UTF-8，但语言不保证内容一定有效 UTF-8；byte 是 `uint8` 别名，rune 是 `int32` 别名、通常表示 Unicode 码点。“字符”必须先明确指字节、码点还是用户感知的字形。

## 学习目标与前置

- 区分 `len(s)` 的字节数与 rune 数；
- 正确遍历 UTF-8、切字节、转换 `[]byte`/`[]rune`；
- 根据 I/O、哈希、文本处理选择表示；
- 识别 NGF `CapitalizeString` 的 ASCII 前提和 Unicode 边界。

前置：[[10-数组与切片的类型差异]]。

## 1. 三种表示

```go
s := "猫a"
fmt.Println(len(s))         // 4 个字节
fmt.Println([]byte(s))      // UTF-8 编码字节
fmt.Println([]rune(s))      // [猫 a] 两个码点
```

string 可包含任意字节并且不可原地修改。`s[i]` 返回第 i 个 byte，不是第 i 个 Unicode 字符。

```go
for byteIndex, r := range s {
	fmt.Printf("%d %c\n", byteIndex, r)
}
```

range 解码 UTF-8，index 是 rune 起始**字节偏移**。无效编码会产生 `utf8.RuneError`，步进规则由语言规范定义。

### 转换成本与可变性

- `[]byte(s)`：得到可修改字节序列，常用于 I/O、哈希、协议；
- `string(b)`：得到不可变字符串值；
- `[]rune(s)`：解码全部码点，方便按码点索引，但需要额外内存；
- 子串 `s[a:b]` 仍按字节边界，切在 UTF-8 中间会得到无效文本。

> [!warning]
> Unicode 码点也不等于用户看到的一个字形。组合字符和 emoji 序列可能由多个 rune 构成；真正的 grapheme cluster 处理需要专门库/规则。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import (
	"fmt"
	"unicode"
	"unicode/utf8"
)

func capitalizeRune(s string) string {
	if s == "" {
		return s
	}
	r, size := utf8.DecodeRuneInString(s)
	if r == utf8.RuneError && size == 1 {
		return s // 保留无效输入；生产代码可选择返回 error
	}
	return string(unicode.ToUpper(r)) + s[size:]
}

func main() {
	for _, s := range []string{"gateway", "éclair", "猫"} {
		fmt.Printf("%q bytes=%d runes=%d upper=%q\n",
			s, len(s), utf8.RuneCountInString(s), capitalizeRune(s))
	}
}
```

```bash
gofmt -w main.go
go run main.go
# "gateway" bytes=7 runes=7 upper="Gateway"
# "éclair" bytes=7 runes=6 upper="Éclair"
# "猫" bytes=3 runes=1 upper="猫"
```

该函数按首个码点处理，不承诺语言学上的标题大小写或多码点大小写映射。

## 3. 常用模式

### 3.1 透明字节处理

哈希、压缩、网络帧不关心文字，使用 `[]byte`。NGF `URLHash` 就把 URL string 转为 bytes 后计算 SHA-256。

### 3.2 UTF-8 流式遍历

只需逐码点检查时直接 `range string`，避免先分配 `[]rune`。

### 3.3 按码点编辑

确实需要随机访问/反转码点时转 `[]rune`，编辑后转回 string。先确认 grapheme cluster 不是需求。

### 3.4 ASCII 协议快速路径

HTTP token、十六进制、受 schema 约束的 Kind/标识符若明确为 ASCII，可按 byte 处理。必须把约束放在入口校验、类型注释或测试中，不能靠调用者“通常传英文”。

## 4. NGF：`CapitalizeString` 是 byte 级实现

焦点：`ngf:internal/framework/helpers/helpers.go:CapitalizeString`。

```go
// NGF 原样短源码，不是独立 demo
func CapitalizeString(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}
```

逐步看：

1. 空串先返回，避免 `s[:1]` 越界；
2. `s[:1]` 取第一个**字节**；
3. 对 ASCII 小写首字母，ToUpper 得到大写字母；
4. 拼接剩余字节。

CodeGraph 显示生产调用位于 graph 的 Gateway/GatewayClass/HTTPRoute/TLSRoute 校验等路径，典型用途是把内部资源 kind/条件消息中的英文标识首字母大写。`internal/framework/helpers/helpers_test.go:TestCapitalizeString` 是直接测试锚点。

### Unicode 失败边界

若首字符是多字节 UTF-8，例如 `é` 或 `猫`，`s[:1]` 切断编码。把无效前缀交给 `strings.ToUpper` 再拼回剩余字节，结果不能保证是有效 UTF-8。因此该 helper 只能在调用输入确认为 ASCII 时复用。

当前函数注释只说“first letter”，未在类型上表达 ASCII。源码调用呈现 ASCII 风格资源名，但这不足以证明所有未来输入都受 ASCII 验证。若 helper 要成为一般文本函数，应改为 rune-aware 实现并添加非 ASCII/无效 UTF-8 测试；这属于改代码建议，本教程不修改生产实现。

## 5. string、byte、rune 选择矩阵

| 任务 | 首选 | 原因 |
|---|---|---|
| map key、不可变标签 | string | 可比较、不可变 |
| 文件/网络/哈希数据 | `[]byte` | 可变、标准 I/O 接口通用 |
| 逐 Unicode 码点检查 | range string | 流式解码、少分配 |
| 码点级重排 | `[]rune` | 可索引/修改码点 |
| 用户可见字形切分 | 专用 Unicode 分段 | rune 仍可能拆开字形 |

## 6. 边界与误区

- `len("猫") == 3`，不是 1；
- `s[0]` 是 byte，格式化 `%c` 可能显示无意义字符；
- `range` index 是字节偏移，不是第几个 rune；
- string 可含无效 UTF-8，入站边界如需文本必须验证 `utf8.ValidString`；
- 大小写不是简单一对一字节替换；区域化规则更复杂；
- 频繁 string/[]byte 转换可能分配，先保证正确，再 profile。

## 7. 迁移判断

- **直接复用**：明确 ASCII 协议的 byte 操作；哈希前转 []byte。
- **条件复用**：按 rune 首字母大写，适合码点语义但不等于完整标题规则。
- **不可照搬**：把 NGF `s[:1]` 用于用户自然语言或未知 UTF-8 输入。

## 8. 练习与答案

1. `len("é")` 通常是多少？UTF-8 下为 2；`utf8.RuneCountInString` 为 1。
2. 如何安全取首个 rune 和剩余字符串？`r, size := utf8.DecodeRuneInString(s)`，剩余 `s[size:]`。
3. 为什么 URLHash 用 []byte 而非 []rune？SHA-256 处理字节；URL 的确切编码字节决定摘要。
4. 如何为 CapitalizeString 固定边界？增加 ASCII 输入校验/命名或改 rune 实现，并测试非 ASCII 与无效 UTF-8。

## 源码证据索引

- `ngf:internal/framework/helpers/helpers.go:CapitalizeString`、`URLHash`。
- 生产调用：`ngf:internal/controller/state/graph/gateway.go`、`gateway_listener.go`、`gatewayclass.go`、`httproute.go` 的验证/构建函数。
- `ngf:internal/framework/helpers/helpers_test.go:TestCapitalizeString`。

上一章：[[14-map空struct集合模式]] · 下一章：[[16-for-range整数range与迭代]] · 延伸：[[52-encoding-json与模型转换]]
