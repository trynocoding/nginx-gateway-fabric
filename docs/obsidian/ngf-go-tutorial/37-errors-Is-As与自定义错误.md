---
title: "37 errors.Is、errors.As 与自定义错误类型"
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

# 37 errors.Is、errors.As 与自定义错误类型

## 语法

Is 比较链中的哨兵语义；As 提取可赋值的具体错误类型。

**说明性片段：**

```go
if errors.Is(err, context.Canceled) { return }

var target *ParseError
if errors.As(err, &target) { _ = target.Line }
```

## NGF 中的应用

位置：`ngf:internal/controller/status/updater.go:ErrFailedAssert`

**原样源码：**

```go
var ErrFailedAssert = errors.New("type assertion failed")
```

类型断言失败 → panic 包装 ErrFailedAssert；其他边界用 errors.Is/As 分类取消或状态错误。

## 相关测试

`internal/controller/status/updater_test.go`
