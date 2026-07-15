---
title: "02 package、导出规则与 internal 边界"
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

# 02 package、导出规则与 internal 边界

## 语法

包名组织命名空间，首字母大写控制导出；internal 由 Go 工具链限制跨父目录导入。

**说明性片段：**

```go
package demo

var Exported = 1 // 跨包可见
var hidden = 2   // 仅本包可见
```

## NGF 中的应用

位置：`ngf:internal/framework/helpers/helpers.go:package helpers`

**原样源码：**

```go
package helpers
```

调用方导入 internal/framework/helpers → 只能访问 GetPointer 等导出名 → 编译器执行 internal 可见性检查。

## 相关测试

`internal/framework/helpers/helpers_test.go`
