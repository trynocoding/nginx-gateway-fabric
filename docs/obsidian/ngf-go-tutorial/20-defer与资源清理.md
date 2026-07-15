---
title: "20 defer 与资源清理"
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

# 20 defer 与资源清理

## 语法

defer 在外围函数返回前按后进先出执行，适合把清理紧邻资源获取。

**说明性片段：**

```go
f, err := os.Open(name)
if err != nil { return err }
defer f.Close()
```

## NGF 中的应用

位置：`ngf:internal/framework/waf/fetch/s3/s3.go:Fetcher.FetchBundle`

**原样源码：**

```go
defer result.Body.Close()
```

S3 GetObject 成功 → 立即登记 Body.Close → ReadAll → 任一路径返回时清理。

## 相关测试

`internal/framework/waf/fetch/s3/s3_test.go`
