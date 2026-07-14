#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    printf 'ERROR: %s requires Bash; run it directly or with bash, not sh.\n' "$0" >&2
    exit 2
fi

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${NGF_DEBUG_NAMESPACE:-nginx-gateway}"
SELECTOR="${NGF_DEBUG_SELECTOR:-app.kubernetes.io/name=nginx-gateway-fabric}"
POD_NAME="${NGF_DEBUG_POD:-}"
TARGET_CONTAINER="${NGF_DEBUG_TARGET_CONTAINER:-nginx-gateway}"
DEBUG_CONTAINER="${NGF_DEBUG_CONTAINER:-dlv}"
DEBUG_IMAGE="${NGF_DEBUG_IMAGE:-dlv-debug:edge}"
DEBUG_PORT="${NGF_DEBUG_PORT:-40000}"
LOCAL_PORT="${NGF_DEBUG_LOCAL_PORT:-40000}"
FORWARD_ADDRESS="${NGF_DEBUG_FORWARD_ADDRESS:-0.0.0.0}"
KUBE_CONTEXT="${NGF_DEBUG_CONTEXT:-}"
WAIT_TIMEOUT="${NGF_DEBUG_WAIT_TIMEOUT:-60}"
CONTINUE_ON_ATTACH=true
ALLOW_LEADER_ELECTION=false
PORT_FORWARD=true
DRY_RUN=false

TEMP_DIR=""
PROXY_PID=""
PROXY_PORT=""

usage() {
    cat <<EOF
Attach a Delve ephemeral container to the NGINX Gateway Fabric control-plane Pod.

Usage:
  ${SCRIPT_NAME} [options]

Options:
  -n, --namespace NAME          Kubernetes namespace (default: ${NAMESPACE})
  -l, --selector SELECTOR       Pod label selector (default: ${SELECTOR})
      --pod NAME                Attach to this Pod instead of auto-discovering one
  -c, --target-container NAME   Target container name (default: ${TARGET_CONTAINER})
  -i, --image IMAGE             Delve image (default: ${DEBUG_IMAGE})
      --debug-container NAME    Ephemeral container name (default: ${DEBUG_CONTAINER})
      --debug-port PORT         Delve port inside the Pod (default: ${DEBUG_PORT})
      --local-port PORT         Host port used by port-forward (default: ${LOCAL_PORT})
      --address ADDRESS         Port-forward listen address (default: ${FORWARD_ADDRESS})
      --context NAME            Explicit kubectl context
      --timeout SECONDS         Wait timeout for Delve startup (default: ${WAIT_TIMEOUT})
      --pause-on-attach         Leave NGF paused after attach instead of auto-continuing
      --allow-leader-election   Attach even when leader election is enabled (unsafe for breakpoints)
      --no-port-forward         Inject/verify Delve and exit without port-forwarding
      --dry-run                 Discover and validate, then print the PATCH without applying it
  -h, --help                    Show this help

Environment variables:
  NGF_DEBUG_NAMESPACE, NGF_DEBUG_SELECTOR, NGF_DEBUG_POD,
  NGF_DEBUG_TARGET_CONTAINER, NGF_DEBUG_CONTAINER, NGF_DEBUG_IMAGE,
  NGF_DEBUG_PORT, NGF_DEBUG_LOCAL_PORT, NGF_DEBUG_FORWARD_ADDRESS,
  NGF_DEBUG_CONTEXT, NGF_DEBUG_WAIT_TIMEOUT

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --context kind-kind --local-port 40001
  ${SCRIPT_NAME} --pod nginx-gateway-nginx-gateway-fabric-abc --no-port-forward
  ${SCRIPT_NAME} --address 127.0.0.1 --pause-on-attach

Security:
  The default address 0.0.0.0 exposes an unauthenticated Delve endpoint on every
  host interface. Restrict TCP access to the selected local port with a firewall.
EOF
}

log() {
    local level="$1"
    shift
    printf '[%s] %-5s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${level}" "$*" >&2
}

info() {
    log INFO "$@"
}

warn() {
    log WARN "$@"
}

die() {
    log ERROR "$@"
    exit 1
}

cleanup_proxy() {
    if [[ -n "${PROXY_PID}" ]] && kill -0 "${PROXY_PID}" 2>/dev/null; then
        kill "${PROXY_PID}" 2>/dev/null || true
        wait "${PROXY_PID}" 2>/dev/null || true
    fi
    PROXY_PID=""
}

cleanup() {
    cleanup_proxy
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_command() {
    local command_name="$1"
    command -v "${command_name}" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
}

validate_port() {
    local name="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[0-9]+$ ]] || ((value < 1 || value > 65535)); then
        die "${name} must be an integer between 1 and 65535; got: ${value}"
    fi
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[0-9]+$ ]] || ((value < 1)); then
        die "${name} must be a positive integer; got: ${value}"
    fi
}

while (($# > 0)); do
    case "$1" in
        -n | --namespace)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            NAMESPACE="$2"
            shift 2
            ;;
        -l | --selector)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            SELECTOR="$2"
            shift 2
            ;;
        --pod)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            POD_NAME="$2"
            shift 2
            ;;
        -c | --target-container)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            TARGET_CONTAINER="$2"
            shift 2
            ;;
        -i | --image)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            DEBUG_IMAGE="$2"
            shift 2
            ;;
        --debug-container)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            DEBUG_CONTAINER="$2"
            shift 2
            ;;
        --debug-port)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            DEBUG_PORT="$2"
            shift 2
            ;;
        --local-port)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            LOCAL_PORT="$2"
            shift 2
            ;;
        --address)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            FORWARD_ADDRESS="$2"
            shift 2
            ;;
        --context)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            KUBE_CONTEXT="$2"
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            WAIT_TIMEOUT="$2"
            shift 2
            ;;
        --pause-on-attach)
            CONTINUE_ON_ATTACH=false
            shift
            ;;
        --allow-leader-election)
            ALLOW_LEADER_ELECTION=true
            shift
            ;;
        --no-port-forward)
            PORT_FORWARD=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            PORT_FORWARD=false
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            die "Unknown option: $1 (use --help for usage)"
            ;;
    esac
done

(($# == 0)) || die "Unexpected positional arguments: $*"

validate_port "debug port" "${DEBUG_PORT}"
validate_port "local port" "${LOCAL_PORT}"
validate_positive_integer "timeout" "${WAIT_TIMEOUT}"

require_command kubectl
require_command jq
require_command curl

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT}" ]]; then
    KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

kube() {
    "${KUBECTL[@]}" "$@"
}

CURRENT_CONTEXT="${KUBE_CONTEXT}"
if [[ -z "${CURRENT_CONTEXT}" ]]; then
    CURRENT_CONTEXT="$(kubectl config current-context)"
fi
[[ -n "${CURRENT_CONTEXT}" ]] || die "No kubectl context is selected"

CLUSTER_SERVER="$(
    kube config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true
)"

info "Kubernetes context: ${CURRENT_CONTEXT}"
info "Kubernetes API: ${CLUSTER_SERVER:-unknown}"
info "Namespace: ${NAMESPACE}"

CAN_GET_PODS="$(kube auth can-i get pods -n "${NAMESPACE}")"
[[ "${CAN_GET_PODS}" == "yes" ]] || die "Current identity cannot get Pods in namespace ${NAMESPACE}"

discover_pod() {
    local pods_json
    local -a pod_names=()

    if [[ -n "${POD_NAME}" ]]; then
        kube get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null
        return
    fi

    pods_json="$(
        kube get pods \
            -n "${NAMESPACE}" \
            -l "${SELECTOR}" \
            --field-selector=status.phase=Running \
            -o json
    )"

    mapfile -t pod_names < <(
        jq -r '.items[] | select(.metadata.deletionTimestamp == null) | .metadata.name' <<<"${pods_json}"
    )

    case "${#pod_names[@]}" in
        0)
            kube get pods -n "${NAMESPACE}" -l "${SELECTOR}" -o wide >&2 || true
            die "No non-terminating Running Pod matched selector: ${SELECTOR}"
            ;;
        1)
            POD_NAME="${pod_names[0]}"
            ;;
        *)
            printf 'Matching Pods:\n' >&2
            printf '  %s\n' "${pod_names[@]}" >&2
            die "More than one Running Pod matched; choose one explicitly with --pod"
            ;;
    esac
}

discover_pod

POD_JSON="$(kube get pod -n "${NAMESPACE}" "${POD_NAME}" -o json)"
POD_PHASE="$(jq -r '.status.phase' <<<"${POD_JSON}")"
[[ "${POD_PHASE}" == "Running" ]] || die "Pod ${POD_NAME} is not Running; phase=${POD_PHASE}"
POD_DELETION_TIMESTAMP="$(jq -r '.metadata.deletionTimestamp // empty' <<<"${POD_JSON}")"
[[ -z "${POD_DELETION_TIMESTAMP}" ]] || \
    die "Pod ${POD_NAME} is terminating; deletionTimestamp=${POD_DELETION_TIMESTAMP}"

if ! jq -e --arg name "${TARGET_CONTAINER}" \
    'any(.spec.containers[]?; .name == $name)' <<<"${POD_JSON}" >/dev/null; then
    AVAILABLE_CONTAINERS="$(jq -r '[.spec.containers[].name] | join(", ")' <<<"${POD_JSON}")"
    die "Target container ${TARGET_CONTAINER} not found; available containers: ${AVAILABLE_CONTAINERS}"
fi

LEADER_ELECTION_DISABLED="$(
    jq -r --arg name "${TARGET_CONTAINER}" '
        (.spec.containers[] | select(.name == $name) | .args // [])
        | index("--leader-election-disable") != null
    ' <<<"${POD_JSON}"
)"

if [[ "${LEADER_ELECTION_DISABLED}" != "true" ]]; then
    if [[ "${ALLOW_LEADER_ELECTION}" == "true" ]]; then
        warn "Leader election is enabled; a breakpoint longer than the renew deadline can restart NGF and kill Delve."
    else
        warn "Leader election is enabled in target container ${TARGET_CONTAINER}."
        warn "Pausing at a breakpoint stops lease renewal, causing 'leader election lost' and debugger disconnects."
        warn "Disable it with:"
        warn "helm upgrade nginx-gateway ${ROOT_DIR}/charts/nginx-gateway-fabric -n ${NAMESPACE} --reuse-values --set nginxGateway.leaderElection.enable=false --wait"
        die "Refusing unsafe attach. Re-run after the rollout, or override with --allow-leader-election."
    fi
else
    info "Leader election is disabled, so breakpoints will not terminate NGF through lease loss"
fi

NODE_NAME="$(jq -r '.spec.nodeName' <<<"${POD_JSON}")"
NODE_ARCH="$(kube get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.architecture}')"
TARGET_READY="$(
    jq -r --arg name "${TARGET_CONTAINER}" \
        '.status.containerStatuses[] | select(.name == $name) | .ready' <<<"${POD_JSON}"
)"

info "Target Pod: ${NAMESPACE}/${POD_NAME}"
info "Target container: ${TARGET_CONTAINER} (ready=${TARGET_READY})"
info "Node: ${NODE_NAME} (${NODE_ARCH})"

if command -v docker >/dev/null 2>&1 && docker image inspect "${DEBUG_IMAGE}" >/dev/null 2>&1; then
    IMAGE_ARCH="$(docker image inspect "${DEBUG_IMAGE}" --format '{{.Architecture}}')"
    if [[ -n "${IMAGE_ARCH}" && "${IMAGE_ARCH}" != "${NODE_ARCH}" ]]; then
        die "Debug image architecture ${IMAGE_ARCH} does not match node architecture ${NODE_ARCH}"
    fi
    info "Local debug image architecture: ${IMAGE_ARCH}"
fi

build_patch() {
    local shell_command

    shell_command='PID=$(pgrep -o -f "^/usr/bin/gateway") && echo "attaching-to-pid=$PID" && exec dlv attach "$PID"'
    if [[ "${CONTINUE_ON_ATTACH}" == "true" ]]; then
        shell_command+=' --continue'
    fi
    shell_command+=" --headless --listen 127.0.0.1:${DEBUG_PORT} --api-version=2 --accept-multiclient --only-same-user=false"

    jq -n \
        --arg name "${DEBUG_CONTAINER}" \
        --arg image "${DEBUG_IMAGE}" \
        --arg target "${TARGET_CONTAINER}" \
        --arg shellCommand "${shell_command}" \
        '{
            spec: {
                ephemeralContainers: [
                    {
                        name: $name,
                        command: ["/bin/sh", "-c", $shellCommand],
                        image: $image,
                        imagePullPolicy: "Never",
                        targetContainerName: $target,
                        stdin: true,
                        tty: true,
                        securityContext: {
                            capabilities: {add: ["SYS_PTRACE"]},
                            runAsNonRoot: false
                        }
                    }
                ]
            }
        }'
}

PATCH_BODY="$(build_patch)"
jq -e . <<<"${PATCH_BODY}" >/dev/null

EPHEMERAL_EXISTS="$(
    jq -r --arg name "${DEBUG_CONTAINER}" \
        'any(.spec.ephemeralContainers[]?; .name == $name)' <<<"${POD_JSON}"
)"

ephemeral_state() {
    kube get pod -n "${NAMESPACE}" "${POD_NAME}" -o json |
        jq -r --arg name "${DEBUG_CONTAINER}" '
            [
                .status.ephemeralContainerStatuses[]?
                | select(.name == $name)
                | if .state.running then
                      "running"
                  elif .state.waiting then
                      "waiting:" + (.state.waiting.reason // "unknown")
                  elif .state.terminated then
                      "terminated:" + (.state.terminated.reason // "unknown")
                  else
                      "unknown"
                  end
            ][0] // "pending"
        '
}

validate_existing_ephemeral_container() {
    local existing_image
    local existing_target
    local existing_command
    local state

    existing_image="$(
        jq -r --arg name "${DEBUG_CONTAINER}" \
            '.spec.ephemeralContainers[] | select(.name == $name) | .image' <<<"${POD_JSON}"
    )"
    existing_target="$(
        jq -r --arg name "${DEBUG_CONTAINER}" \
            '.spec.ephemeralContainers[] | select(.name == $name) | .targetContainerName' <<<"${POD_JSON}"
    )"
    existing_command="$(
        jq -r --arg name "${DEBUG_CONTAINER}" \
            '.spec.ephemeralContainers[] | select(.name == $name) | .command | join(" ")' <<<"${POD_JSON}"
    )"

    [[ "${existing_target}" == "${TARGET_CONTAINER}" ]] || \
        die "Existing ${DEBUG_CONTAINER} targets ${existing_target}, not ${TARGET_CONTAINER}"
    [[ "${existing_command}" == *"127.0.0.1:${DEBUG_PORT}"* ]] || \
        die "Existing ${DEBUG_CONTAINER} does not listen on requested debug port ${DEBUG_PORT}"

    if [[ "${existing_image}" != "${DEBUG_IMAGE}" ]]; then
        warn "Existing ${DEBUG_CONTAINER} uses image ${existing_image}; requested image is ${DEBUG_IMAGE}"
    fi

    state="$(ephemeral_state)"
    if [[ "${state}" == terminated:* ]]; then
        kube logs -n "${NAMESPACE}" "${POD_NAME}" -c "${DEBUG_CONTAINER}" --tail=80 >&2 || true
        die "Existing ephemeral container is ${state}. Recreate the Pod before attaching again."
    fi

    info "Reusing existing ephemeral container ${DEBUG_CONTAINER} (state=${state})"
}

start_proxy() {
    local proxy_log
    local attempt

    TEMP_DIR="$(mktemp -d)"
    proxy_log="${TEMP_DIR}/kubectl-proxy.log"

    "${KUBECTL[@]}" proxy --address=127.0.0.1 --port=0 >"${proxy_log}" 2>&1 &
    PROXY_PID=$!

    for ((attempt = 0; attempt < 100; attempt++)); do
        if ! kill -0 "${PROXY_PID}" 2>/dev/null; then
            cat "${proxy_log}" >&2
            die "kubectl proxy exited before becoming ready"
        fi

        PROXY_PORT="$(
            sed -nE 's/.*127\.0\.0\.1:([0-9]+).*/\1/p' "${proxy_log}" | head -n 1
        )"
        if [[ -n "${PROXY_PORT}" ]] && \
            curl --fail --silent "http://127.0.0.1:${PROXY_PORT}/version" >/dev/null 2>&1; then
            return
        fi

        sleep 0.1
    done

    cat "${proxy_log}" >&2
    die "Timed out waiting for kubectl proxy"
}

inject_ephemeral_container() {
    local can_patch
    local api_url
    local patch_response

    can_patch="$(kube auth can-i patch pods/ephemeralcontainers -n "${NAMESPACE}")"
    [[ "${can_patch}" == "yes" ]] || \
        die "Current identity cannot patch pods/ephemeralcontainers in namespace ${NAMESPACE}"

    start_proxy
    api_url="http://127.0.0.1:${PROXY_PORT}/api/v1/namespaces/${NAMESPACE}/pods/${POD_NAME}/ephemeralcontainers"
    patch_response="${TEMP_DIR}/patch-response.json"

    info "Injecting ${DEBUG_CONTAINER} from image ${DEBUG_IMAGE}"
    if ! curl \
        --fail-with-body \
        --silent \
        --show-error \
        --request PATCH \
        "${api_url}" \
        --header 'Content-Type: application/strategic-merge-patch+json' \
        --data "${PATCH_BODY}" \
        --output "${patch_response}"; then
        cat "${patch_response}" >&2 || true
        die "Kubernetes rejected the ephemeral container PATCH"
    fi

    if ! jq -e --arg name "${DEBUG_CONTAINER}" \
        'any(.spec.ephemeralContainers[]?; .name == $name)' "${patch_response}" >/dev/null; then
        cat "${patch_response}" >&2
        die "PATCH response does not contain ephemeral container ${DEBUG_CONTAINER}"
    fi

    cleanup_proxy
}

wait_for_delve() {
    local deadline=$((SECONDS + WAIT_TIMEOUT))
    local state
    local logs

    while ((SECONDS < deadline)); do
        state="$(ephemeral_state)"

        if [[ "${state}" == terminated:* ]]; then
            kube logs -n "${NAMESPACE}" "${POD_NAME}" -c "${DEBUG_CONTAINER}" --tail=80 >&2 || true
            die "Delve ephemeral container terminated before becoming ready: ${state}"
        fi

        if [[ "${state}" == "running" ]]; then
            logs="$(
                kube logs -n "${NAMESPACE}" "${POD_NAME}" -c "${DEBUG_CONTAINER}" --tail=80 2>&1 || true
            )"
            if [[ "${logs}" == *"API server listening at: 127.0.0.1:${DEBUG_PORT}"* ]]; then
                info "Delve is listening inside the Pod on 127.0.0.1:${DEBUG_PORT}"
                printf '%s\n' "${logs}" >&2
                return
            fi
        fi

        sleep 1
    done

    kube get pod -n "${NAMESPACE}" "${POD_NAME}" -o wide >&2 || true
    kube logs -n "${NAMESPACE}" "${POD_NAME}" -c "${DEBUG_CONTAINER}" --tail=80 >&2 || true
    die "Timed out after ${WAIT_TIMEOUT}s waiting for the Delve API server"
}

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Dry run: no Kubernetes resources will be changed"
    printf '%s\n' "${PATCH_BODY}"
    exit 0
fi

if [[ "${EPHEMERAL_EXISTS}" == "true" ]]; then
    validate_existing_ephemeral_container
else
    inject_ephemeral_container
fi

wait_for_delve

POD_JSON="$(kube get pod -n "${NAMESPACE}" "${POD_NAME}" -o json)"
TARGET_READY="$(
    jq -r --arg name "${TARGET_CONTAINER}" \
        '.status.containerStatuses[] | select(.name == $name) | .ready' <<<"${POD_JSON}"
)"

if [[ "${TARGET_READY}" != "true" ]]; then
    warn "Target container is not Ready. Connect to Delve and run 'continue'; an older existing attach may be paused."
elif [[ "${CONTINUE_ON_ATTACH}" == "true" ]]; then
    info "Target container remains Ready because Delve was started with --continue"
fi

if [[ "${PORT_FORWARD}" != "true" ]]; then
    info "Delve attach completed; port-forward was disabled"
    exit 0
fi

CAN_PORT_FORWARD="$(kube auth can-i create pods/portforward -n "${NAMESPACE}")"
[[ "${CAN_PORT_FORWARD}" == "yes" ]] || \
    die "Current identity cannot create pods/portforward in namespace ${NAMESPACE}"

if [[ "${FORWARD_ADDRESS}" == "0.0.0.0" ]]; then
    warn "Delve will be exposed without authentication on all host interfaces at TCP ${LOCAL_PORT}."
    warn "Restrict access to trusted source addresses with a host or network firewall."
fi

info "Starting port-forward: ${FORWARD_ADDRESS}:${LOCAL_PORT} -> ${POD_NAME}:${DEBUG_PORT}"
info "Remote client command: dlv connect <host-ip>:${LOCAL_PORT}"
info "Press Ctrl+C to stop port-forwarding; the Delve ephemeral container will remain attached."

kube port-forward \
    --address="${FORWARD_ADDRESS}" \
    -n "${NAMESPACE}" \
    "pod/${POD_NAME}" \
    "${LOCAL_PORT}:${DEBUG_PORT}"
