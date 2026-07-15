---
title: "58 Ginkgo/Gomega 的行为测试组织"
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

# 58 Ginkgo/Gomega 的行为测试组织

## 语法

Describe/Context/It 按行为层次组织，BeforeEach 建立场景；断言表达可观察结果而非实现细节。

**说明性片段：**

```go
var _ = Describe("Reconciler", func() {
	It("sends an upsert event", func() {
		Expect(event).NotTo(BeNil())
	})
})
```

## NGF 中的应用

位置：`ngf:internal/framework/controller/reconciler.go:Reconciler.Reconcile`

**原样源码：**

```go
func (r *Reconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
```

Ginkgo 场景启动 Reconcile → fake Getter/EventCh 控制输入 → Gomega 断言 Upsert/Delete/取消结果。

## 相关测试

`internal/framework/controller/reconciler_test.go`
