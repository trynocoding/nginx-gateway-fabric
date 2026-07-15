---
title: "53 text-template 与配置生成"
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

# 53 text/template 与配置生成

> [!abstract] 核心结论
> `text/template` 把可信模板与数据分开：Parse 建语法树，Execute 写结果。它不会为 NGINX 语法或 shell/HTML 上下文自动转义；输入必须先映射为已验证的模板模型，渲染后还要通过项目/数据面的配置验证。

## 学习目标与前置

前置：[[19-函数值闭包与高阶函数]]、[[51-io接口与资源所有权]]、[[52-encoding-json与模型转换]]。完成后应能：

- 使用 `New/Parse/Execute`、`Must` 和 `Option("missingkey=error")`；
- 解释 dot、`$` 根变量、range/with 作用域和 `{{- -}}` 空白裁剪；
- 区分 `text/template` 与 `html/template` 的 escaping；
- 追踪 NGF RateLimitPolicy 从 API 值到 settings、模板、include file；
- 说明 Go 渲染成功、配置语义有效、NGINX reload 成功是三层不同事实。

## 1. Parse 与 Execute 是两个阶段

```go
tmpl, err := template.New("name").Parse(source)
err = tmpl.Execute(writer, data)
```

Parse 发现未闭合 action、未知函数等模板定义错误；Execute 发现字段/方法不可访问、函数返回 error、writer 写失败等运行错误。同一解析后的 Template 可并发 Execute，只要解析完成后不再修改它，并且各次 writer/data 的并发安全由调用方保证。

## 2. 可独立运行 demo

**可运行示例（Go 1.26.0，标准库）：**

```go
package main

import (
	"bytes"
	"fmt"
	"text/template"
)

type Rule struct {
	Zone string
	Rate string
}

type Config struct {
	Prefix string
	Rules  []Rule
}

const source = `{{- range $i, $rule := .Rules }}
limit_req_zone $binary_remote_addr zone={{ $.Prefix }}_{{ $i }}:10m rate={{ $rule.Rate }}; # {{ $rule.Zone }}
{{- end }}`

func main() {
	tmpl := template.Must(template.New("nginx").Option("missingkey=error").Parse(source))
	data := Config{
		Prefix: "demo",
		Rules:  []Rule{{Zone: "api", Rate: "10r/s"}, {Zone: "admin", Rate: "2r/s"}},
	}
	var out bytes.Buffer
	if err := tmpl.Execute(&out, data); err != nil {
		panic(err)
	}
	fmt.Print(out.String())
}
```

运行会生成两条 `limit_req_zone`。range 内 dot 是当前 Rule，`$.Prefix` 始终回到根 Config，`$i` 是索引；`{{-` 删除 action 左侧空白。已在 `go1.26.0` 执行并核对输出。

## 3. dot、变量与作用域

- `{{.Field}}`：当前 dot 的导出字段、无参方法或 map key；
- `{{range .Items}}`：每次迭代把 dot 改为元素；
- `{{with .Optional}}`：非空时把 dot 改为该值；
- `{{$root := .}}`：保存当前值；`$` 默认是 Execute 的根参数；
- `{{template "child" .}}`：调用关联模板并显式传 dot。

变量作用域到对应 control structure 的 end；模板调用不会自动继承调用点局部变量。不要让模板承担复杂业务计算，先在 Go 中生成专用 view model。

## 4. 空值和 missing key

if/with/range 把 false、0、nil、空 slice/map/string 视为空。range 空集合执行 else 分支。map 缺 key 的默认行为可能输出 `<no value>`；配置生成通常应设置 `Option("missingkey=error")`，避免静默生成残缺指令。

Struct 不存在字段通常会在 Execute 报错。`Must` 只处理 Parse 返回的 error，不能让 Execute 变成无错误。

## 5. Must 的适用边界

```go
var tmpl = template.Must(template.New("fixed").Parse(fixedSource))
```

模板是编译进二进制的常量时，解析失败属于程序员/构建错误，包初始化 panic 能尽早暴露。模板来自用户、ConfigMap 或磁盘时不能 Must，应返回带文件/模板名上下文的 error。

NGF 的固定模板在 package init 用 `template.Must`；`internal/framework/helpers/helpers.go:MustExecuteTemplate` 对 Execute error 也 panic。这把模板字段不匹配/执行失败定义为内部不变量，而非用户可恢复错误。

## 6. 空白裁剪

`{{-` 裁掉 action 前的空白，`-}}` 裁掉后的空白，连字符旁必须有空格才能表示 trim marker。对 NGINX 配置，额外空行通常无害，但错误裁剪可能把两个 token 或两条指令粘在一起。测试应断言关键完整行，而不仅是“包含字段值”。

## 7. Escaping 与注入边界

> [!danger] text/template 不做上下文安全转义
> 数据中的分号、换行、引号、`$` 会按文本写出。模板语法本身不会把它变成合法安全的 NGINX token。

`html/template` 知道 HTML/URL/JS 上下文并自动 escaping，但不能用它“保护 NGINX”。NGF 需要在 API/schema/validation 层限制 duration、size、变量名、snippet 等，再把规范化字段交给模板。

模板应是可信代码，用户输入作为 data；不要让用户输入直接成为 Parse 的模板 source。Snippets 是刻意允许的原始 NGINX 内容，风险与校验边界和普通 typed field 不同。

## 8. NGF 实例：RateLimitPolicy 生成链

`internal/controller/nginx/config/policies/ratelimit/generator.go` 的因果链：

1. 固定 `rateLimitHTTPTemplate/rateLimitReqTemplate` 在包初始化 Parse + Must；
2. `getRateLimitSettings` 把版本化 API Policy 转成私有模板模型，补 `10m`、`100r/s`、`$binary_remote_addr` 默认；
3. `generate` 根据 HTTP/Server/Location 选择不同 Template，并跳过不适用的 shadow policy；
4. `helpers.MustExecuteTemplate(tmpl, settings)` 得到 bytes；
5. 生成稳定文件名，作为 policy include 交给总 Generator；
6. `GeneratorImpl.executeConfigTemplates` 按目标路径聚合片段，生成带 hash/size/permissions 的 `agent.File`。

模板只负责格式，policy 适用层级、默认值和文件名在 Go 代码中完成。这种分工让模板保持可读，也让业务规则可单测。

## 9. 配置验证不是一个步骤

`internal/controller/nginx/config/generator.go:GeneratorImpl.Generate` 的注释明确要求调用方在生成前用 validation package 验证 Configuration；无效配置可能 reload 失败或带来恶意配置。

需要区分：

| 层 | 能证明什么 | 不能证明什么 |
|---|---|---|
| Template Parse | action 语法正确 | 数据值安全、NGINX 语法正确 |
| Execute | 字段访问与写入成功 | 指令组合合法 |
| Go validator/CRD schema | 已编码的领域规则 | 所有动态 NGINX 模块语义 |
| 生成测试 | 期望指令文本存在 | 真正 binary 能 reload |
| 数据面应用结果 | 特定 NGINX 接受或拒绝 | 所有未来输入都正确 |

仓库内没有在这个 generator 函数中直接调用 `nginx -t`；配置通过 agent 发送到数据面，应用失败再进入 reload/status 错误路径。不要把字符串单测写成“已验证 NGINX”。

## 10. 测试与修改边界

`internal/controller/nginx/config/policies/ratelimit/generator_test.go:TestGenerate` 覆盖默认/显式字段、多 rule、不同 context 与 shadow policy。修改字段需同步：API/schema validator → settings 映射 → template → 期望文件测试；若改文件路径/包含关系，还要检查总 Generator。

## 11. 练习与检查点

1. 把 demo 的 `$.Prefix` 改为 `.Prefix`。检查 Execute 失败，因为 range 中 dot 是 Rule。
2. 给模板输入 Rate `10r/s; return 200`，观察原样输出。检查点：escaping 不能替代字段 validator。
3. 删除 NGF settings 默认赋值，预测生成文本和测试失败位置。

## 源码证据索引与下一步

| 主题 | 证据 |
|---|---|
| 固定模板 Parse/Must | `internal/controller/nginx/config/policies/ratelimit/generator.go` 顶部模板与 `tmpl*` |
| API → view model | 同文件 `getRateLimitSettings` |
| Execute panic 边界 | `internal/framework/helpers/helpers.go:MustExecuteTemplate` |
| 总文件生成 | `internal/controller/nginx/config/generator.go:executeConfigTemplates` |
| 渲染测试 | `internal/controller/nginx/config/policies/ratelimit/generator_test.go:TestGenerate` |

上一章：[[52-encoding-json与模型转换]] · 下一章：[[54-reflect与运行时类型注册]]
