---
title: "50 slices、maps 与 cmp"
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

# 50 slices、maps 与 cmp

> [!abstract] 核心结论
> Go 1.26 的 `slices`、`maps`、`cmp` 把常见容器操作变成泛型标准库 API。它们大多是浅层操作：复制容器不等于复制元素指向的对象；Equal 通常把 nil 与空容器视为内容相等，但 JSON、API patch 和项目约定仍可能区分二者。

## 学习目标与前置

前置：[[10-数组与切片的类型差异]]、[[12-切片共享与防御性复制]]、[[13-map-comma-ok与缺失值]]、[[29-泛型函数与类型推断]]。完成后应能：

- 使用 `slices.Equal/Clone/Delete/SortFunc` 与 `maps.Equal/Clone/Copy/DeleteFunc`；
- 用 `cmp.Compare/Less/Or` 写排序和默认选择；
- 解释 nil/空在相等、clone、序列化中的不同语义；
- 读懂 NGF `mergedWAFBundles` 的覆盖顺序、浅复制和 nil 返回契约。

## 1. API 地图

| 目的 | slice | map |
|---|---|---|
| 内容相等 | `slices.Equal` / `EqualFunc` | `maps.Equal` / `EqualFunc` |
| 浅复制 | `slices.Clone` | `maps.Clone` |
| 删除 | `slices.Delete/DeleteFunc` | 内建 `delete` / `maps.DeleteFunc` |
| 排序 | `slices.Sort/SortFunc/SortStableFunc` | 先收集 key 再排序 |
| 合并 | `append` / `Concat` | `maps.Copy(dst, src)` |

这些函数不会凭空提供深拷贝、稳定顺序或并发安全。

## 2. 可独立运行 demo

**可运行示例（Go 1.26.0，标准库）：**

```go
package main

import (
	"cmp"
	"fmt"
	"maps"
	"slices"
)

type Rule struct {
	Name     string
	Priority int
}

func main() {
	var nilSlice []int
	emptySlice := []int{}
	fmt.Println(slices.Equal(nilSlice, emptySlice))
	fmt.Println(slices.Clone(nilSlice) == nil, slices.Clone(emptySlice) == nil)

	values := []int{1, 2, 3, 4}
	values = slices.Delete(values, 1, 3)
	fmt.Println(values)

	dst := map[string]int{"same": 1, "old": 9}
	maps.Copy(dst, map[string]int{"same": 2, "new": 3})
	fmt.Println(dst["same"], slices.Sorted(maps.Keys(dst)))

	rules := []Rule{{"b", 2}, {"a", 2}, {"c", 1}}
	slices.SortFunc(rules, func(a, b Rule) int {
		return cmp.Or(cmp.Compare(a.Priority, b.Priority), cmp.Compare(a.Name, b.Name))
	})
	fmt.Println(rules)
}
```

运行 `go run main.go`。预期依次看到：nil/空内容相等；Clone 保留各自 nil 性；删除得到 `[1 4]`；`same` 被覆盖为 2 且 key 已排序；Rule 先按 Priority、再按 Name 排序。已在 `go1.26.0` 执行验证。

## 3. 相等不是同一对象

`slices.Equal` 比较长度与逐元素 `==`，nil slice 和长度 0 的非 nil slice 都没有元素，所以相等。`maps.Equal` 同理把 nil map 与空 map 视为内容相等。

但以下问题不同：

- `slice == nil` / `map == nil` 检查表示状态；
- JSON 默认把 nil slice 编为 `null`、空 slice 编为 `[]`；nil map 是 `null`、空 map 是 `{}`；
- Kubernetes merge/patch 语义可能区分“未设置”和“明确为空”；
- `slices.Equal` 不适用于元素不可比较的类型，要用 `EqualFunc`。

因此测试选 `Equal` 还是 `BeNil`，本身就在声明契约。

## 4. Clone、Copy 与浅层所有权

`slices.Clone` 和 `maps.Clone` 新建容器，但元素是按赋值复制。若元素是 pointer、slice、map、interface，内层对象仍共享：

```go
original := map[string]*Rule{"x": {Name: "before"}}
clone := maps.Clone(original)
clone["x"].Name = "after" // original 中同一个 *Rule 也变化
```

**说明性示例，不是独立 demo。** 真正深拷贝需要逐元素定义语义；通用反射式 deep copy 未必理解锁、缓存和资源句柄。

`maps.Copy(dst, src)` 只写入/覆盖 src 中的 key，不删除 dst 独有 key。覆盖规则由调用顺序表达：后 copy 的 source 胜出。

## 5. 删除与容量边界

`slices.Delete(s, i, j)` 删除半开区间 `[i,j)` 并返回新长度的 slice，调用者必须接住返回值。Go 当前实现会清零被移出长度范围的元素，避免引用型元素被底层数组意外长期持有；但底层数组容量仍可能复用，不能据此建立隔离语义。

删除大量元素后若希望释放大 backing array，可 clone 剩余部分。是否值得要由 profile 和生命周期决定，不能每次删除都机械复制。

map 的内建 `delete(m, key)` 对 nil map 和不存在 key 都安全；向 nil map 写入才 panic。`maps.DeleteFunc` 适合按 key/value 谓词批量删。

## 6. 排序与 cmp

`cmp.Compare(a,b)` 返回负/零/正，适合 `slices.SortFunc`。`cmp.Or` 返回第一个非零值，能组合多级排序；它不是布尔短路表达式。

- `slices.SortFunc` 不保证相等元素保持原顺序；需要时用 `SortStableFunc`；
- map 迭代顺序未定义，稳定输出要先 `maps.Keys`，再 `slices.Sorted`；
- `cmp.Less` 对浮点 NaN 有定义顺序，但领域层是否允许 NaN仍需单独校验；
- 排序 comparator 必须一致、传递，否则结果不可依赖。

## 7. NGF 实例：`mergedWAFBundles`

`internal/controller/state/change_processor.go:(*ChangeProcessorImpl).mergedWAFBundles` 合并两类缓存：

1. `latestGraph.ReferencedWAFBundles`：上一轮 graph 保存的 bundle；
2. `cfg.PolledWAFBundles()`：poller 取得的更新版本；
3. 两边长度都为 0 时返回 nil；
4. 新建容量为两者长度之和的 map；
5. 先 `maps.Copy(merged, graphBundles)`；
6. 再 `maps.Copy(merged, polledBundles)`，同 key 时 polled 胜出。

**生产源码关键片段：**

```go
merged := make(map[graph.WAFBundleKey]*graph.WAFBundleData, len(graphBundles)+len(polledBundles))
maps.Copy(merged, graphBundles)
maps.Copy(merged, polledBundles)
```

新 map 防止后续增删 key 直接修改两个 source map；value 是 `*WAFBundleData`，所以这是浅复制。函数注释给出的不变量是：graph rebuild 不能用较旧 graph 数据覆盖 poller 的新数据，尤其 re-fetch 失败时仍保留较新的 bundle。

`Process` 在 `BuildGraph` 前调用该函数，把结果作为 `previousWAFBundles` 输入。整个调用受 ChangeProcessor 的锁保护；`maps.Copy` 自身并不提供线程安全。

## 8. 测试如何固定契约

`internal/controller/state/change_processor_test.go:TestMergedWAFBundles` 覆盖：

- 两边 nil 与两边 empty 均返回 nil；
- poller 函数 nil、返回 nil；
- 仅 graph、仅 poller、key 不相交；
- key 重叠时 polled pointer 胜出。

这里测试同时用了 `BeNil` 和 key/value 比较，说明 nil 返回不是偶然优化，而是被固定的可观察行为。

## 9. 常见误区与迁移边界

> [!warning] 标准库容器函数不等于不可变数据结构
> Clone 后元素可能共享；Copy 后 dst 仍可被修改；并发读写 map 仍需同步。

**可直接迁移：** 用 Copy 顺序表达 overlay 优先级；稳定输出先排序 key。**有条件迁移：** nil/空归一化，必须确认 API 语义。**不要复制：** 认为 `maps.Clone(map[K]*T)` 已深拷贝 T。

## 10. 练习与检查点

1. 给 demo 增加 nil/空 map 的 `maps.Equal` 与 JSON 输出。检查内容相等但 JSON 不同。
2. 把 Rule 排序改为 Priority 降序、Name 升序。检查 comparator 的符号只翻转第一关键字。
3. 修改 `mergedWAFBundles` 的 copy 顺序并运行测试。检查重叠 key 用例失败，说明优先级由顺序决定。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| overlay 合并与 nil 契约 | `internal/controller/state/change_processor.go:mergedWAFBundles` |
| 构造调用点 | `internal/controller/state/change_processor.go:Process` |
| 覆盖顺序测试 | `internal/controller/state/change_processor_test.go:TestMergedWAFBundles` |
| 其他防御性 map Copy | `internal/framework/waf/poller/manager.go:GetAllBundleUpdates`、bundle cache snapshot |

上一章：[[49-EventLoop批处理与状态所有权]] · 下一章：[[51-io接口与资源所有权]]
