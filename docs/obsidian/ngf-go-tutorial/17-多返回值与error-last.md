---
title: "17 多返回值与 error-last 约定"
tags: [nginx-gateway-fabric, go-1-26, tutorial]
status: complete
note_type: syntax-tutorial
go_version: "1.26.0"
repo_revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
sources:
  - repo: nginx-gateway-fabric
    revision: "df175d68064b54c369b6cb2a6c83c8c1b2ab26ca"
    dirty: false
---

# 17 多返回值与 error-last 约定

## 语法

函数可返回多个结果；惯例把 error 放最后，让成功值和失败原因同时进入静态签名。

**说明性片段：**

```go
func parse(s string) (string, error) {
	if s == "" { return "", errors.New("empty") }
	return s, nil
}
```

## NGF 中的应用

位置：`ngf:internal/framework/waf/fetch/s3/s3.go:parseS3URI`

**原样源码：**

```go
func parseS3URI(uri string) (bucket, key string, err error) {
```

S3 URI → parseS3URI 返回 bucket/key/error → 调用者只在 err == nil 时构建请求。

## 相关测试

`internal/framework/waf/fetch/s3/s3_test.go`
