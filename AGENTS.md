# Repository Guidelines

## Project Structure & Module Organization

NGINX Gateway Fabric is a Go-based Gateway API controller with NGINX as the data plane. Main entrypoint code lives in `cmd/gateway/`; controller, graph, NGINX, and framework packages live in `internal/`. API definitions are under `apis/`, Kubernetes YAML under `config/` and `deploy/`, Helm assets under `charts/nginx-gateway-fabric/`, examples under `examples/`, and developer docs under `docs/developer/`. Integration and conformance tests use a separate module in `tests/`.

## Build, Test, and Development Commands

Use `make help` to list targets and variables. Common commands:

- `make build`: builds the `gateway` binary into `build/out/`.
- `make unit-test`: runs Go unit tests for `cmd/` and `internal/` with race, shuffle, and coverage output.
- `make fmt`: runs `go fmt ./...`.
- `make lint`: runs `golangci-lint` with the repository configuration and `--fix`.
- `make dev-all`: runs deps, formatting, vet, lint, Go tests, and njs checks.
- `make create-kind-cluster` and `make install-ngf-local-build`: create a local kind cluster and install locally built images.

## Coding Style & Naming Conventions

Follow `docs/developer/go-style-guide.md`, Effective Go, and Go Code Review Comments. Format Go with gofmt/gofumpt/goimports through configured tooling. Keep lines at or under 120 characters where practical. Prefer table-driven tests, clear package boundaries, context propagation, concrete return types, and dependency injection. Branch names should use label-driven prefixes such as `bug/`, `fix/`, or `feature/`.

## Testing Guidelines

Use Ginkgo and Gomega for BDD-style coverage of exported interfaces; use standard Go tests for gaps and edge cases. Add `t.Parallel()` to standard tests and subtests unless ordering is required, and document exceptions. Unit tests should cover positive and negative paths and reproduce bug fixes before the fix. Run `make unit-test`; inspect `cover.html` when coverage matters. See `tests/README.md` for conformance testing.

## Commit & Pull Request Guidelines

Recent commits use imperative, user-facing summaries, often ending with a PR number, for example `Update NGINX OSS to 1.31.2 (#5471)`. Final commit messages should include a summary plus `Problem:`, `Solution:`, and optional `Testing:` sections as described in `docs/developer/pull-request.md`. Fill out the PR template, link the related issue unless trivial, add release-note text for user-visible changes, and keep review updates in focused commits before squashing.

## Security & Configuration Tips

Do not commit customer-identifying data, credentials, JWTs, private NGINX Plus files, or local cluster secrets. Redact IPs, ports, names, and URLs from external reports. For NGINX Plus or WAF workflows, provide required files and environment variables locally, such as `PLUS_USAGE_ENDPOINT`, `license.jwt`, or `dockerconfig.jwt`.
