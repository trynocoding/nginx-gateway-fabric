---
title: "16 for range、整数 range 与迭代语义"
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

# 16 for range、整数 range 与迭代语义

> [!abstract]
> Go 只有 `for` 循环，既可写条件、三段式、无限循环，也可 `range` 数组/slice/string/map/channel、整数及迭代函数。不同 range 源返回的值和顺序不同；Go 1.22 起每次迭代变量拥有新的变量语义，Go 1.26 模块已包含它。

## 学习目标与前置

- 掌握 `for` 的主要形式和 break/continue；
- 预测不同 range 源产生的 index/key/value；
- 使用 `for i := range n`，理解 0 到 n-1；
- 解释 NGF Service predicate 为何先比较长度再用整数 range 构建集合。

前置：[[10-数组与切片的类型差异]]、[[13-map-comma-ok与缺失值]]。

## 1. `for` 的基本形式

```go
for i := 0; i < 3; i++ {} // 三段式
for ready() {}             // 条件式
for {}                     // 无限循环，靠 break/return 退出
```

`break` 退出最近循环或 select；`continue` 进入下一轮。带标签的 break/continue 可控制外层循环，但应少用并保持名字清楚。

### range slice/array

```go
for i, v := range values {}
for i := range values {}
for _, v := range values {}
```

index 从 0 递增；v 是元素值副本。若要修改 slice 元素，用 `values[i].Field = ...`，修改 v 本身通常不影响原元素。

### range string/map/channel

- string：`index, rune`，index 是 UTF-8 字节偏移；
- map：`key, value`，顺序不保证；
- channel：每轮接收一个值，直到 channel 关闭；nil channel 会永久阻塞。

## 2. 整数 range

```go
for i := range 5 {
	fmt.Println(i) // 0,1,2,3,4
}
```

range 整数 n 迭代从 0 到 n-1；n <= 0 时零次。它适合“按次数/索引”循环，省去 `i := 0; i < n; i++`。若需要自定义起点、步长或反向，仍用三段式。

## 3. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import "fmt"

func main() {
	ports := []int{80, 443, 8080}
	for i := range len(ports) {
		fmt.Printf("ports[%d]=%d\n", i, ports[i])
	}

	for byteIndex, r := range "A猫" {
		fmt.Printf("byte=%d rune=%c\n", byteIndex, r)
	}

	for range -2 { // 负整数：零次
		panic("unreachable")
	}
}
```

```bash
gofmt -w main.go
go run main.go
# ports[0]=80
# ports[1]=443
# ports[2]=8080
# byte=0 rune=A
# byte=1 rune=猫
```

失败例：循环 `for i := range len(old) { _ = new[i] }` 若 new 更短会越界。必须先证明长度关系，或直接 range 需要索引的那个 slice。

## 4. 常用模式

### 4.1 index + value 只读遍历

用于日志、转换与筛选。不要在循环中 append 到同一 slice 又假定 range 会访问新元素；range 的迭代范围应按规范理解并避免自修改混乱。

### 4.2 只用 index 原地更新

```go
for i := range items {
	items[i].Ready = true
}
```

对 struct slice，修改 `v.Ready` 只改副本；index 写回才改元素。

### 4.3 integer range 重复 n 次

适合测试生成、按同长度的多个 slice 比较。n 的来源必须可信，避免负数被悄悄当零次掩盖上游错误。

### 4.4 map range + 排序实现确定性

先收集 key、排序，再按 key 访问 map；配置生成、快照和 golden test 尤其需要确定性。

## 5. 迭代变量与闭包

Go 1.22 起，使用 `:=` 声明的 range 迭代变量每轮是新的变量，减少闭包捕获“最终值”陷阱。仍需注意：

- 显式在循环外声明再用 `=` 赋值，可能继续共享同一变量；
- 捕获的元素若是指针，多个指针可能本来就指同一对象；
- 并发启动还涉及 goroutine 退出、同步和数据竞争，见 [[40-goroutine启动与退出责任]]。

Go 1.23 还支持 range over function 迭代器；它适合封装遍历而不暴露容器。本章 NGF 实例使用的是整数 range，不展开自定义迭代器协议。

## 6. NGF：ServiceChangedPredicate 的整数 range

焦点：`ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`。

函数先完成 nil 和类型断言检查，然后：

```go
// NGF 缩写源码，不是独立 demo
if len(oldPorts) != len(newPorts) {
	return true
}

for i := range len(oldSvc.Spec.Ports) {
	// 分别读取 oldPorts[i] 与 newPorts[i]，构造两个 portInfo set
}
```

长度先比较是整数 range 安全访问两个 slice 的必要前置。如果长度不同，Service 的相关配置已变化，直接返回 true；相同时 i 对两侧都有效。

循环并不直接按位置判等，而把 `servicePort/targetPort/appProtocol` 组成可比较 `portInfo`，分别放入两个 `map[portInfo]struct{}`，最后做集合差。因此端口仅重排不会触发 reconcile，而字段变化、增加或删除会触发。

```text
UpdateEvent old/new
  → nil/type 检查
  → 长度不同：changed=true
  → range len(oldPorts)
      → nil AppProtocol 归一为空字符串
      → 构建 old/new portInfo sets
  → 集合比较 → changed true/false
```

`AppProtocol` 指针先 nil 检查，未设置归一为空字符串；这意味着 nil 与指向 `""` 在此比较中等价，是明确的局部语义。`internal/framework/controller/predicate/service_test.go:TestServiceChangedPredicate_Update` 与相关端口变化测试是行为锚点。

### 为什么用 `range len(...)` 而不是 `range oldPorts`

循环只需要 index，同时访问 old/new 同位置元素；整数 range 直接表达“重复共同长度次”。写 `for i := range oldPorts` 也能达到相同效果，当前写法体现项目使用现代语言特性，不带额外性能保证。

## 7. 边界与误区

- map range 无序；不能拿第一次遍历结果做稳定配置；
- range string 的 index 不是 rune 序号；
- range slice 的 value 是副本，修改 struct value 不改原元素；
- integer range n<=0 零次，若负数是非法状态应先校验；
- range channel 只有关闭才结束，发送者/关闭者所有权必须明确；
- 修改迭代中的 map 具有规范定义的有限行为但可读性差，通常分阶段处理。

## 8. 迁移判断

- **直接复用**：同长度双 slice 索引、按 index 原地更新、整数次数循环。
- **条件复用**：用集合忽略顺序，前提是业务确实不关心重复项和顺序；Service ports 在 Kubernetes API 中有其约束。
- **不可照搬**：未经长度证明同时索引两个 slice；依赖 map 遍历顺序。

## 9. 练习与答案

1. `for i := range 0` 执行几次？0 次。
2. 修改 `for _, v := range []Item` 中的 `v.Field` 会改原 slice 吗？对 struct 值不会；用 index。
3. 为什么 Service 端口重排不触发？比较的是 portInfo 集合，不是位置。
4. old/new 长度检查能否省略？不能；当前循环索引两侧，且长度变化本身应触发。

## 源码证据索引

- `ngf:internal/framework/controller/predicate/service.go:ServiceChangedPredicate.Update`、`portInfo`。
- `ngf:internal/framework/controller/predicate/service_test.go:TestServiceChangedPredicate_Update`。
- 注册入口：`ngf:internal/controller/manager.go:registerControllers`（Service predicate 进入 controller）。
- 相关机制：`ngf:internal/framework/controller/register.go:Register`。

上一章：[[15-string-byte与rune]] · 下一章：[[17-多返回值与error-last]] · 延伸：[[40-goroutine启动与退出责任]]、[[61-Predicate与事件过滤]]
