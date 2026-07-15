---
title: "52 encoding-json 与模型转换"
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

# 52 encoding/json 与模型转换

> [!abstract] 核心结论
> `json.Marshal/Unmarshal` 依据导出字段和 tag 在 Go 值与 JSON 之间转换。默认 Unmarshal 忽略未知字段；配置入口若要 fail-fast，应使用 Decoder 的 `DisallowUnknownFields` 并拒绝尾随值。JSON round-trip 是协议转换，不是通用 deep copy 或领域映射。

## 学习目标与前置

前置：[[07-struct-tag与JSON字段语义]]、[[08-指针nil与可选字段]]、[[50-slices-maps与cmp]]。完成后应能：

- 使用 Marshal、Unmarshal、Encoder、Decoder；
- 解释 `json:"name,omitempty"`、`omitzero`、`-` 与指针可选字段；
- 严格拒绝 unknown fields 和多个顶层 JSON 值；
- 分辨 API DTO、领域模型与默认值 overlay；
- 读懂 NGF `updateControlPlane` 为什么把同一 Spec marshal 后覆盖到带默认值的 Spec。

## 1. 基础编码规则

只有导出字段会参与默认编码。tag 的第一段改名，选项控制省略：

```go
type Config struct {
	Name     string            `json:"name"`
	Labels   map[string]string `json:"labels,omitempty"`
	Limits   Limits            `json:"limits,omitzero"`
	Internal string            `json:"-"`
}
```

**说明性示例。** `omitempty` 省略 false、0、nil pointer/interface、长度 0 的 string/array/slice/map；非指针 struct 通常不会因 `omitempty` 被省略。`omitzero` 使用类型零值或 `IsZero() bool` 判定，适合省略零 struct。两者可同时写，满足任一条件就省略。

## 2. 可独立运行 demo：严格配置解析

**可运行示例（Go 1.26.0，标准库）：**

```go
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

type Limits struct{ Max int `json:"max"` }

type Config struct {
	Name   string            `json:"name"`
	Labels map[string]string `json:"labels,omitempty"`
	Limits Limits            `json:"limits,omitzero"`
}

func decodeStrict(input string) (Config, error) {
	decoder := json.NewDecoder(strings.NewReader(input))
	decoder.DisallowUnknownFields()
	var cfg Config
	if err := decoder.Decode(&cfg); err != nil {
		return Config{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return Config{}, errors.New("expected one JSON value")
	}
	return cfg, nil
}

func main() {
	cfg, err := decodeStrict(`{"name":"ngf","labels":{}}`)
	data, _ := json.Marshal(cfg)
	fmt.Println(string(data), err)
	_, err = decodeStrict(`{"name":"ngf","extra":true}`)
	fmt.Println(err != nil)
}
```

预期输出 `{"name":"ngf"} <nil>` 和 `true`：空 labels 被 `omitempty` 省略，零 Limits 被 `omitzero` 省略，未知 extra 被拒绝。已在 `go1.26.0` 执行验证。

## 3. Marshal 的失败边界

`json.Marshal(v)` 返回 `([]byte,error)`。常见失败包括：

- channel、func、complex 等不支持类型；
- float NaN/Inf；
- 自定义 `MarshalJSON` 返回错误；
- 循环引用。

map key 输出会被排序以形成确定字节序，但不应把 JSON 文本顺序当业务协议。HTML 字符默认会被转义；需要流式输出可用 Encoder 并按安全需求设置 `SetEscapeHTML`。

## 4. Unmarshal 与 Decoder

`json.Unmarshal(data,&dst)` 要求非 nil pointer。不存在的 JSON 字段通常保留 dst 原值；这使它能做 overlay，但复用非零 dst 也容易留下旧 slice/map 数据。类型不匹配返回 `UnmarshalTypeError`，此前部分字段可能已写入，错误后不应把 dst 当完整有效对象。

默认规则：

- 未知 object key 被忽略；
- object key 匹配优先 tag，再不区分大小写匹配字段名；
- `null` 对 pointer/map/slice/interface 设 nil，对许多非指针标量无效果；
- 重复 key 会按后出现者继续替换/合并，不能依赖它表达合法配置。

面向外部配置通常使用 Decoder + `DisallowUnknownFields`，并第二次 Decode 检查 EOF，防止 `{} {}` 被当成一个成功配置。

## 5. API 模型与领域模型

JSON tag 是 wire contract，不等于内部领域模型。推荐边界：

1. 外部 JSON/Kubernetes API 解码到版本化 API struct；
2. schema/CEL/显式 validator 检查语法与组合；
3. 显式转换成 graph/dataplane 等内部模型；
4. 内部模型不必携带所有 JSON tag 和兼容字段。

用 JSON round-trip 在不同 struct 间映射会静默丢字段、受 tag 名控制、产生分配，还绕过编译器字段检查。只有“协议语义就是所需语义”时才考虑。

## 6. NGF 实例：`updateControlPlane`

`internal/controller/config_updater.go:updateControlPlane` 先构造默认值：

```go
controlConfig := ngfAPI.NginxGatewaySpec{
	Logging: &ngfAPI.Logging{
		Level: helpers.GetPointer(ngfAPI.ControllerLogLevelInfo),
	},
}
```

若 Kubernetes `NginxGateway` 存在，函数将 `cfg.Spec` Marshal，再 Unmarshal 到这个非零 `controlConfig`。源和目标都是 `ngfAPI.NginxGatewaySpec`，`Logging`/`Level` 都有 `omitempty`：未设置字段不会出现在 JSON 中，因此不会覆盖预置的 info 默认。

然后函数解引用最终 Level，显式 `validateLogLevel`，再调用注入的 `logLevelSetter.SetLevel`。JSON 只承担“按 API tag 做 overlay”；语义校验仍是下一阶段。

## 7. Unknown fields 的准确边界

该路径没有 Decoder，也没有 `DisallowUnknownFields`。但输入不是原始 JSON，而是 Kubernetes 客户端已经构造的 typed `NginxGatewaySpec`；Marshal 只能输出该 Go 类型已知字段。因此这里不能证明“NGF 接收原始 unknown field 并拒绝”。

原始 CRD 请求的未知字段是否保留/拒绝，属于 Kubernetes structural schema 与 API server 边界，而非 `updateControlPlane` 的 json.Unmarshal。迁移到读取本地 JSON 配置的程序时，必须自己加严格 Decoder。

## 8. 测试与失败路径

`internal/controller/config_updater_test.go:TestUpdateControlPlane` 覆盖：

- 用户显式 debug 覆盖默认 info；
- invalid level 被 validate 拒绝，setter 不调用；
- cfg nil 时使用默认并记录 Kubernetes warning event；
- setter 失败转成字段错误。

目前类型中没有会让 Marshal 失败的字段，因此错误分支主要是防未来自定义 JSON 行为/字段变化；测试未专门制造 Marshal/Unmarshal error。

## 9. 常见误区与迁移边界

> [!warning] “成功解码”不等于“配置有效”
> JSON 只证明语法与基本类型能转换。端口范围、互斥字段、引用存在性仍需 validator。

- `omitempty` 是编码规则，不会在解码时自动填默认；
- pointer 常用于区分未设置和显式零值；
- Marshal/Unmarshal deep copy 会丢未导出字段并触发自定义方法；
- 日志中直接打印 JSON 可能泄漏 token、Secret data 和证书私钥。

**直接迁移：** API 解码后显式验证。**条件迁移：** 同类型 JSON overlay，需测试 tag、null、默认值。**不要复制：** 用 JSON 代替领域转换函数。

## 10. 练习与检查点

1. 去掉 demo 的 `DisallowUnknownFields`，检查 extra 被静默忽略。
2. 把 `Limits` 改为 pointer 并比较 nil、`&Limits{}` 的 `omitempty/omitzero` 输出。
3. 为 `updateControlPlane` 画 `typed Spec → JSON → default Spec → validate → setter`，标出每层能发现哪些错误。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| JSON 默认值 overlay | `internal/controller/config_updater.go:updateControlPlane` |
| API tags/可选字段 | `apis/v1alpha1/nginxgateway_types.go:NginxGatewaySpec`、`Logging` |
| 语义校验 | `internal/controller/config_updater.go:validateLogLevel` |
| 覆盖与失败测试 | `internal/controller/config_updater_test.go:TestUpdateControlPlane` |

上一章：[[51-io接口与资源所有权]] · 下一章：[[53-text-template与配置生成]]
