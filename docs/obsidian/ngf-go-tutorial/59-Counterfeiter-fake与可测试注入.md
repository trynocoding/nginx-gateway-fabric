---
title: "59 Counterfeiter、fake 与可测试依赖注入"
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

# 59 Counterfeiter、fake 与可测试依赖注入

## 语法

生成 fake 记录调用、参数和返回值；它依赖先有窄接口和构造注入，不能替代良好边界。

**说明性片段：**

```go
//counterfeiter:generate . Reader

type Reader interface {
	Get(context.Context, string) ([]byte, error)
}
```

## NGF 中的应用

位置：`ngf:internal/controller/nginx/agent/grpc/messenger/messenger.go:Messenger counterfeiter directive`

**原样源码：**

```go
//counterfeiter:generate . Messenger
```

业务依赖 Messenger → Counterfeiter 生成 FakeMessenger → 测试配置返回 channel/error 并断言调用。

## 相关测试

`internal/controller/nginx/agent/grpc/messenger/messengerfakes/fake_messenger.go`
