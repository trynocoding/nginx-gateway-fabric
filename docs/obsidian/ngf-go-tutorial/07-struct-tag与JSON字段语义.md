---
title: "07 struct tag 与 JSON 字段语义"
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

# 07 struct tag 与 JSON 字段语义

> [!abstract]
> struct tag 是附着在字段上的字符串元数据；是否生效由 `encoding/json`、validator 或代码生成器解释。`json:"level,omitempty"` 同时指定外部字段名和“空值时省略”，但它不负责默认值或业务校验。

## 学习目标与前置

- 写出 JSON 字段名、`omitempty`、`-` 等常见 tag；
- 预测值字段、指针、slice/map 在 marshal 时何时被省略；
- 区分 tag、Kubebuilder 注释与 Go 类型各自职责；
- 追踪 NGF `Logging.Level` 从 JSON 到默认合并和校验。

前置：[[06-struct与复合字面量]]。完整 JSON 转换见 [[52-encoding-json与模型转换]]。

## 1. tag 的语法与读取者

```go
type Config struct {
	LogLevel string `json:"logLevel,omitempty" validate:"oneof=info debug"`
}
```

反引号包住整个 tag；空格分隔不同键。Go 编译器保存 tag，但不解释 `json` 或 `validate` 的含义。`encoding/json` 只读取 `json`，某个校验库才可能读取 `validate`。

### `encoding/json` 常见形式

| tag | 效果 |
|---|---|
| ``json:"level"`` | 外部名固定为 `level` |
| ``json:"level,omitempty"`` | 空值时 marshal 省略 |
| ``json:"-"`` | 始终忽略字段 |
| 无 tag | 默认使用导出字段名 |

未导出字段即使有 tag，标准 JSON 编码器也不会序列化。

### `omitempty` 的关键语义

对 `false`、数值 0、空字符串、nil 指针、长度 0 的 slice/map 等，marshal 时会省略。于是值字段无法区分“用户没写”和“用户明确写零值”。指针可保留这个差异：nil 表示缺失，非 nil 指向 false/0/空串表示显式设置。

> [!warning]
> `omitempty` 只影响编码输出，不会在解码时自动填默认值，也不会验证 enum。

## 2. 可独立运行的最小 demo（Go 1.26）

```go
// 可运行示例；Go 1.26.0
package main

import (
	"encoding/json"
	"fmt"
)

type Config struct {
	Name    string `json:"name"`
	Enabled bool   `json:"enabled,omitempty"`
	Limit   *int   `json:"limit,omitempty"`
	Secret  string `json:"-"`
}

func main() {
	zero := 0
	values := []Config{
		{Name: "absent"},
		{Name: "explicit-zero", Limit: &zero, Secret: "not serialized"},
	}

	for _, v := range values {
		data, err := json.Marshal(v)
		if err != nil {
			panic(err)
		}
		fmt.Println(string(data))
	}
}
```

```bash
gofmt -w main.go
go run main.go
# {"name":"absent"}
# {"name":"explicit-zero","limit":0}
```

这证明 nil 指针被省略，而指向 0 的指针保留字段。`Secret` 因 `json:"-"` 不出现。

### 失败例

把 tag 写成普通双引号嵌套或漏掉反引号会导致语法错误。写成 `json:"Level"` 虽能编译，却改变外部协议；tag 拼写通常不会由编译器发现，应靠序列化测试或生成器校验。

## 3. 常用模式

### 3.1 API 字段稳定命名

Go 使用 `LogLevel`，JSON 使用 `logLevel`，使语言惯例和外部协议各自清晰。重命名 Go 字段时保持 tag 可避免协议变化。

### 3.2 指针表达可选标量

当缺失、false/0/空串含义不同，用 `*bool/*int/*string`。如果二态足够，值字段更简单。

### 3.3 `json:"-"` 隔离进程内字段

缓存、函数、锁、敏感材料不应进入 JSON。对秘密数据不能只依赖 tag，还需避免日志和其他序列化路径。

### 3.4 自定义 Marshal/Unmarshal

当协议需要版本迁移、联合类型或严格格式时实现接口。代价是逻辑复杂，必须测试对称性、错误路径和未知字段策略。

## 4. NGF：`Logging.Level` 不只是一个 tag

焦点：`ngf:apis/v1alpha1/nginxgateway_types.go:Logging`。

```go
// NGF 缩写源码，不是独立 demo
type Logging struct {
	// +kubebuilder:default=info
	Level *ControllerLogLevel `json:"level,omitempty"`
}
```

这里有三种元数据/类型机制：

| 元素 | 解释者 | 作用 |
|---|---|---|
| `*ControllerLogLevel` | Go 类型系统/JSON | nil 与显式值可区分 |
| `json:"level,omitempty"` | JSON 编码器 | 外部名 `level`，nil 编码时省略 |
| `+kubebuilder:default=info` | CRD 生成与 API server | schema 默认化 |

此外 `ControllerLogLevel` 上的 Enum 标记负责 schema 值域。运行时 `updateControlPlane` 又构造默认 `info`，把用户 `Spec` marshal 后覆盖到默认对象，再调用 `validateLogLevel`。

```text
YAML/JSON `logging.level`
  → 解码为 Logging.Level 指针
  → updateControlPlane 先准备默认 info
  → marshal/unmarshal 叠加用户字段
  → 解引用并 validateLogLevel
  → logLevelSetter.SetLevel(string(level))
```

为什么项目不只依赖 schema 默认：控制器也处理 `cfg == nil`（配置对象被删除）和测试直接构造的 Go 对象；进程内默认保证这些路径行为一致。`internal/controller/config_updater_test.go:TestUpdateControlPlane` 覆盖显式 debug、非法值、nil 配置和 setter 失败。

### `inline` 的 Kubernetes 特例

同文件 `NginxGateway` 的 `metav1.TypeMeta` 字段使用 ``json:",inline"``。`inline` 不是标准
`encoding/json` 通用选项，而是 Kubernetes 序列化/生成生态约定；不要看到 tag 就假设标准库支持相同语义。

## 5. 边界与迁移

- 可直接复用：稳定外部名、用指针表达缺失、为协议写序列化测试。
- 条件复用：marshal/unmarshal 叠加默认值；要确认嵌套对象、null、slice/map 的覆盖语义符合需求。
- 不可照搬：认为 Kubebuilder 注释会被普通 Go 程序运行时自动执行。
- 变更 tag 属于协议变更，需检查 CRD、客户端、已有对象和兼容迁移。
- `omitempty` 可能让显式 false 丢失；需要三态时改用指针或专门 optional 类型。

## 6. 练习与答案

1. `Enabled bool` 配合 ``json:"enabled,omitempty"`` 能区分缺失和 false 吗？不能。
2. `Limit *int` 为非 nil、指向 0 时会省略吗？不会，指针本身非空。
3. tag 会校验 `ControllerLogLevel` 只能是 debug/info/error 吗？不会；由 schema 标记和运行时校验负责。
4. 修改 `level` 为 `logLevel` 要检查什么？CRD/schema、序列化测试、已有 manifests、客户端兼容和迁移策略。

## 源码证据索引

- `ngf:apis/v1alpha1/nginxgateway_types.go:Logging`、`ControllerLogLevel`、`NginxGateway`。
- `ngf:internal/controller/config_updater.go:updateControlPlane`、`validateLogLevel`。
- `ngf:internal/controller/config_updater_test.go:TestUpdateControlPlane`、`TestValidateLogLevel`。
- 生成边界：`ngf:apis/v1alpha1/zz_generated.deepcopy.go`（生成文件，不应手改）。

上一章：[[06-struct与复合字面量]] · 下一章：[[08-指针nil与可选字段]] · 延伸：[[52-encoding-json与模型转换]]、[[56-go-generate与生成代码边界]]
