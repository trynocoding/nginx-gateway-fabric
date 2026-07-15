---
title: "14 map[T]struct{} 集合模式"
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

# 14 map[T]struct{} 集合模式

> [!abstract]
> Go 标准语言没有内建 Set 类型；只关心成员资格时常用 `map[T]struct{}`。key 保存成员，空 struct 不承载业务值，comma-ok 判断存在。它适合去重、访问记录和集合运算。

## 学习目标与前置

- 用 map 构造泛型/具体集合；
- 理解 `struct{}{}`、`map[T]bool` 的差异；
- 写去重、交集和重复检测；
- 解释 NGF 端口冲突校验的早失败路径。

前置：[[13-map-comma-ok与缺失值]]。

## 1. 空 struct 与集合表示

`struct{}` 是没有字段的 struct 类型，`struct{}{}` 是它的值。其大小通常为 0，但 map 自身仍有 bucket、key 和运行时元数据成本；不要宣称整个集合“零内存”。

```go
seen := make(map[string]struct{})
seen["gateway"] = struct{}{}
_, exists := seen["gateway"]
delete(seen, "gateway")
```

泛型封装：

```go
type Set[T comparable] map[T]struct{}

func (s Set[T]) Add(v T) { s[v] = struct{}{} }
func (s Set[T]) Has(v T) bool { _, ok := s[v]; return ok }
```

Set 的零值仍是 nil map，`Add` 前必须 make；可以提供 `NewSet` 或把 Add 设计为返回更新值，但不能在值接收者里凭空替换调用者的 nil map。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import "fmt"

func unique[T comparable](in []T) []T {
	seen := make(map[T]struct{}, len(in))
	out := make([]T, 0, len(in))
	for _, value := range in {
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}

func main() {
	fmt.Println(unique([]int{80, 443, 80, 8080, 443}))
}
```

```bash
gofmt -w main.go
go run main.go
# [80 443 8080]
```

输出保留输入首次出现顺序，因为遍历的是 in；若直接 range seen，顺序不稳定。

## 3. 常用模式

### 3.1 重复检测（遇到重复立即失败）

遍历输入，先 Has，再 Add。适合配置校验，错误可定位到首次重复项。

### 3.2 稳定去重

用 set 记录是否见过，但把结果 append 到 slice；不要从 map 反向生成结果，否则丢失顺序。

### 3.3 集合交并差

交集：遍历较小 set，在另一 set comma-ok；并集：把两侧 key 加入新 set；差集：只保留右侧不存在的 key。

### 3.4 图遍历 visited

DFS/BFS 用 `map[NodeID]struct{}` 防环。若还需距离、父节点或状态颜色，就应把 value 换成对应信息，而不是并行维护多个 map。

## 4. `map[T]struct{}` 与 `map[T]bool`

| 方案 | 优点 | 容易误解处 |
|---|---|---|
| `map[T]struct{}` | 明确只有成员资格；value 无业务载荷 | 写法略冗长 |
| `map[T]bool` | `if set[k]` 简洁 | false 可表示“存在但 false”还是“缺失”？ |

若团队只用 true 值，bool map 也可工作；空 struct 更明确表达 set 意图。选择应以可读性和项目惯例为主，内存差异需 benchmark，不要凭感觉优化。

## 5. NGF：`ensureNoPortCollisions`

焦点：`ngf:cmd/gateway/validation.go:ensureNoPortCollisions`。

```go
// NGF 原样短源码，不是独立 demo
func ensureNoPortCollisions(ports ...int) error {
	seen := make(map[int]struct{})
	for _, port := range ports {
		if _, ok := seen[port]; ok {
			return fmt.Errorf("port %d has been defined multiple times", port)
		}
		seen[port] = struct{}{}
	}
	return nil
}
```

数据关系：

```text
CLI 收集多个监听/健康/指标端口
  → 可变参数传给 ensureNoPortCollisions
  → seen 记录已出现 int
  → 首个重复端口立即返回带端口值的错误
  → 全部唯一则 nil
```

这里不需要保存端口的附加信息，所以空 struct 合适。函数没有验证端口范围，那是 `validatePort/validateAnyPort` 等其他函数的责任；集合只负责唯一性。把职责分开使错误更精确，也让测试组合更清楚。

`cmd/gateway/validation_test.go` 覆盖重复与不重复输入。可变参数允许调用点直接传多个来源的端口，详见 [[18-可变参数]]。

### 为什么遇到重复立刻返回

配置启动校验只需报告冲突即可停止，早返回时间 O(k)，空间 O(u)。若产品要求一次报告所有冲突，则需继续遍历并聚合重复值/错误，可能结合 [[38-errors-Join多错误聚合]]；不能直接照搬早失败语义。

## 6. 边界与误区

- key 必须 comparable；slice 不能直接作 set 成员；
- set 赋值会共享 map，clone 才是独立集合；
- nil set 可读不可 Add；构造函数或调用点要 make；
- map 遍历无序，稳定输出需排序或保留输入 slice；
- 并发访问仍需锁/单 goroutine 所有权；空 struct 不改变 map 并发规则；
- 只要还需计数，就应改 `map[T]int`，不要另建 set + count map。

## 7. 迁移判断

- **直接复用**：唯一性检查、visited、稳定去重辅助索引。
- **条件复用**：早失败，前提是只需一个错误。
- **不可照搬**：把 set 当有序集合，或只因“省内存”而牺牲更需要的 value 信息。

## 8. 练习与答案

1. 如何返回所有重复端口？用另一个 duplicates set 避免重复报错，遍历完成后排序返回。
2. 为什么 demo 输出稳定？结果跟随输入遍历 append，不遍历 map。
3. Set[T] 的 T 为什么要 comparable？map key 的语言约束。
4. 需要出现次数时用什么？`map[T]int`，`counts[v]++`。

## 源码证据索引

- `ngf:cmd/gateway/validation.go:ensureNoPortCollisions`。
- 同文件 `validatePort`、`validateAnyPort`（职责边界）。
- `ngf:cmd/gateway/validation_test.go`（端口冲突测试）。
- 另一生产 set：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`。

上一章：[[13-map-comma-ok与缺失值]] · 下一章：[[15-string-byte与rune]] · 延伸：[[18-可变参数]]、[[50-slices-maps与cmp]]
