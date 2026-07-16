---
title: "Advanced Routing 的 NGINX 高级路由匹配机制"
tags: [nginx-gateway-fabric, advanced-routing, nginx, source-analysis]
status: complete
note_type: mechanism
created: 2026-07-16
updated: 2026-07-16
sources:
  - repo: nginx-gateway-fabric
    revision: b6eb18e9b431657b872b84c626a8186587f43c41
    ref: v2.6.5
    dirty: false
runtime:
  context: kind-ngf-demo
  observed_at: 2026-07-16T16:47:41+08:00
  nginx: v1.31.2
  http_conf_sha256: 9ce2740091ee59440a93e355dfe9ca8f65d7ae4c2923f37ca7d98ad87dc63239
  matches_json_sha256: 792b40c3ba75edcc312b0dd6d48ae4a10c3cf74b2dc550fac3c9d0669c8a29dc
aliases:
  - Advanced Routing NGINX 配置解读
  - coffee 路由优先级
---

# Advanced Routing 的 NGINX 高级路由匹配机制

> [!abstract] 核心结论
> 本例的请求选择分三层：先由 NGINX `server_name` 匹配 Host，再由 `location` 匹配路径，最后对同一路径下的 Header、Query、Method 使用 njs 读取 `matches.json` 并内部跳转。正则路径是独立的 NGINX 正则 `location`，它能优先于普通 PathPrefix，因此 `/coffee/latte` 即使带 `version:v2` 也会直接进入 coffee-v1。

## 1. 先掌握四个 NGINX 名词

| 名词 | 在本例中的问题 | 当前答案 |
|---|---|---|
| `server` | 这是哪个域名和端口的虚拟主机？ | `listen 80; server_name cafe.example.com;` |
| `location` | 请求路径属于哪组规则？ | `/coffee`、`/tea` 或正则 `/coffee/[a-z]+` |
| `upstream` | 最终可连接的后端服务器有哪些？ | Ready Pod IP:8080 |
| `proxy_pass` | 当前请求要代理到哪个 upstream？ | `default_coffee-v2-svc_80` 等 |

NGF 额外使用 njs（NGINX JavaScript）处理原生 `location` 不方便表达的 Header、Query 和 Method 组合。

## 2. 第一层：Host 选择 server

**运行中生成配置摘录：**

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 404;
}

server {
    listen 80;
    listen [::]:80;
    server_name cafe.example.com;
    # locations...
}
```

请求必须带 `Host: cafe.example.com` 才进入业务 server。错误 Host 进入 default server 并得到 404。

> [!note] Gateway 没写 hostname 为什么还能限制域名？
> Gateway listener 没有限制 hostname；三个 HTTPRoute 的 `spec.hostnames` 都是 `cafe.example.com`。Graph 计算 listener 与 Route 的 hostname 交集，最终生成这个 `server_name`。

## 3. HTTPRoute 条件的 AND / OR

Gateway API 的组合规则是：

- 一个 `matches` 元素内部的 path、method、headers、queryParams 是 **AND**；
- 同一 rule 中多个 `matches` 元素之间是 **OR**；
- 多条 rule 或多个 Route 同时可匹配时，再按优先级选择。

例如 coffee v2：

```text
(PathPrefix /coffee AND Header version Exact v2)
OR
(PathPrefix /coffee AND Query TEST Exact v2)
→ coffee-v2-svc
```

## 4. PathPrefix 为什么生成两个 location

Gateway API 的 PathPrefix 按路径段匹配。`/coffee` 应匹配：

- `/coffee`
- `/coffee/`
- `/coffee/latte`

但不应匹配 `/coffeeabc`。

NGF 2.6.5 因此生成：

```nginx
location /coffee/ { ... }
location = /coffee { ... }
```

`location = /coffee` 是精确匹配；`location /coffee/` 负责带斜杠的子路径。若只生成原生 `location /coffee`，NGINX 的字符串前缀会误收 `/coffeeabc`。

## 5. 为什么 `/coffee` 需要 njs

相同 Host、相同 PathPrefix `/coffee` 下存在五个候选：

1. Header `version=v2` → v2；
2. Header 正则 → v3；
3. Query `TEST=v2` → v2；
4. Query 正则 → v3；
5. 无额外条件 → v1。

NGF 将它们聚合为同一个 `PathRule`，外部 location 只负责调用 njs：

```nginx
location /coffee/ {
    set $match_key 1_1;
    js_content httpmatches.redirect;
}
```

`matches.json` 的实际内容是：

```json
{
  "1_1": [
    {"redirectPath":"/_ngf-internal-rule1-route0","headers":["version:Exact:v2"]},
    {"redirectPath":"/_ngf-internal-rule1-route1","headers":["headerRegex:RegularExpression:header-[a-z]{1}"]},
    {"redirectPath":"/_ngf-internal-rule1-route2","params":["TEST=Exact=v2"]},
    {"redirectPath":"/_ngf-internal-rule1-route3","params":["queryRegex=RegularExpression=query-[a-z]{1}"]},
    {"redirectPath":"/_ngf-internal-rule1-route4","any":true}
  ]
}
```

njs 从上到下找第一个满足项，然后做内部跳转：

```nginx
location /_ngf-internal-rule1-route0 {
    internal;
    proxy_pass http://default_coffee-v2-svc_80$request_uri;
}
```

`internal` 表示客户端不能直接访问这个路径；`internalRedirect` 也不是 301/302，客户端不会看到第二次 HTTP 跳转。

## 6. 候选为什么按这个顺序排列

`ngf:internal/controller/state/dataplane/sort.go:sortMatchRules` 使用稳定排序：

1. 有 Method 的规则优先；
2. Header 数量更多的优先；
3. Query 参数数量更多的优先；
4. 跨 Route 仍相同时，较老 Route 优先，再按 `namespace/name`；
5. 同一 Route 内仍相同时，稳定排序保留 YAML 中较早出现的 rule/match。

因此：

- Header 候选排在 Query 候选前；
- v2 Header 与 v3 Header 数量相同，保留 YAML 中 v2 在前；
- `any:true` 没有 Header/Query，排到最后充当默认 v1。

当请求同时带：

```http
version: v2
headerRegex: header-a
```

v2 Header 候选先成功，因此进入 coffee-v2。

## 7. Header、Query 和正则的大小写/锚点

njs `httpmatches.js` 的实际语义：

| 条件 | 大小写 | 重复值/正则 |
|---|---|---|
| Header 名 | 不敏感 | NGINX `headersIn` 查找不敏感 |
| Header 值 | 敏感 | 逗号分隔多个值，Exact 查找完全相同的值 |
| Query 名 | 敏感 | `TEST` 与 `test` 不同 |
| Query 值 | 敏感 | 重复参数只比较第一个值 |
| Header/Query 正则 | JavaScript `RegExp.test` | 示例未写 `^...$`，允许子串匹配 |

例如 `header-[a-z]{1}` 不等价于整值约束。若要整值匹配，应显式考虑 `^header-[a-z]{1}$`，并通过 NGF/Gateway API 支持性测试确认。

## 8. 正则路径为什么压过 Header 条件

`HTTPRoute/coffee-regex` 的 path-only 规则只有一个候选，不需要 njs，直接生成：

```nginx
location ~ ^/coffee/[a-z]+ {
    proxy_pass http://default_coffee-v1-svc_80;
}
```

对 `/coffee/latte`：

1. NGINX 找到普通前缀 `/coffee/`；
2. 因普通前缀没有 `^~`，NGINX 继续测试正则 location；
3. `^/coffee/[a-z]+` 匹配；
4. 正则 location 胜出并直接代理到 v1；
5. `/coffee/` 的 njs 根本没有执行，因此 `version:v2` 不参与。

正则只有开头锚点 `^`，没有结尾锚点 `$`。所以 `/coffee/latte123` 也会匹配：`[a-z]+` 匹配 `latte` 后，正则已经成功。

> [!warning] 常见误区
> `coffee-regex` 不是 `/coffee` 规则的“附加条件”，而是独立 Route、独立 path type、独立 NGINX location。把 Header 放在请求上，不会自动让所有匹配该 URI 的 Route 合并条件。

## 9. upstream 为什么直接写 Pod IP

**运行中生成配置摘录：**

```nginx
upstream default_coffee-v2-svc_80 {
    random two least_conn;
    zone default_coffee-v2-svc_80 512k;
    server 10.244.0.10:8080;
    keepalive 16;
}
```

- `random two least_conn`：随机取两个候选，再选择连接较少者；当前每组只有一个 Pod。
- `zone ... 512k`：在 worker 间共享 upstream 运行状态。
- `keepalive 16`：保留到后端的空闲持久连接。
- `server 10.244.0.10:8080`：来自 EndpointSlice，而不是 Service ClusterIP。

NGINX 还传递原 Host 与常见代理头：`X-Forwarded-For`、`X-Real-IP`、`X-Forwarded-Proto`、`X-Forwarded-Host`、`X-Forwarded-Port`。

## 10. 精确请求矩阵

| 请求 | 胜出条件 | 终端后端 |
|---|---|---|
| `/coffee` | `any:true` | coffee-v1 |
| `/coffee` + `version:v2` | Exact Header | coffee-v2 |
| `/coffee?TEST=v2` | Exact Query | coffee-v2 |
| `/coffee` + `headerRegex:header-a` | Regex Header | coffee-v3 |
| `/coffee?queryRegex=query-z` | Regex Query | coffee-v3 |
| `/coffee` + v2 和 regex 两个 Header | v2 Header 排在前 | coffee-v2 |
| `/coffee/latte` + `version:v2` | 正则 path location | coffee-v1 |
| `/coffee/latte123` | 正则无结尾锚点 | coffee-v1 |
| `/coffeeabc` | 不满足路径段前缀 | 404 |
| GET `/tea` | Method GET | tea |
| POST `/tea` | Method POST | tea-post |
| PUT `/tea` | njs 无候选 | 404 |
| 错误 Host `/coffee` | default server | 404 |

## 11. 关联笔记

- 上一篇：[[02-GatewayAPI到NGINX配置生成链路]]
- 实验命令：[[04-kind验证与排障手册]]
- 原始正则 YAML：[[regex-route-yaml]]
- 源码索引：[[99-Advanced-Routing源码索引与术语表]]
