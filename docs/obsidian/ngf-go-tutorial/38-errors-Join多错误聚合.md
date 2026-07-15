---
title: "38 errors.Join 与多错误聚合"
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

# 38 errors.Join 与多错误聚合

## 语法

Join 把多个非 nil 错误组成可被 Is/As 遍历的多叉错误；nil 项会被忽略。

**说明性片段：**

```go
return errors.Join(readErr, closeErr)
```

## NGF 中的应用

位置：`ngf:internal/controller/log_level_setters.go:multiLogLevelSetter.SetLevel`

**原样源码：**

```go
return errors.Join(allErrs...)
```

遍历多个日志级别设置器 → 收集各自失败 → Join → 调用者一次看到全部失败。

## 相关测试

`internal/controller/log_level_setters_test.go`
