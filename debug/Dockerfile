# syntax=docker/dockerfile:1.24
# This Dockerfile builds an image with the dlv debugger. See the debugging guide in the developer docs for details
# on how to use it.
FROM golang:1.26-alpine AS builder

ARG DLV_VERSION=v1.27.0
ARG GOPROXY=https://proxy.golang.org,direct

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOPROXY="${GOPROXY}" go install "github.com/go-delve/delve/cmd/dlv@${DLV_VERSION}"

FROM alpine:latest

COPY --from=builder /go/bin/dlv /usr/bin/

CMD ["sh"]
