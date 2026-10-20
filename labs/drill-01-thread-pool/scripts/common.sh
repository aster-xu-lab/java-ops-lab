#!/usr/bin/env bash
# 公共变量与探测：优先 Docker Compose，否则走本地 Java 进程模式。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${ROOT_DIR}/.run"
EVIDENCE_DIR="${ROOT_DIR}/evidence"
ORDER_PORT="${ORDER_PORT:-8080}"
INVENTORY_PORT="${INVENTORY_PORT:-8081}"
MANAGEMENT_PORT="${MANAGEMENT_PORT:-8082}"
ORDER_URL="${ORDER_URL:-http://127.0.0.1:${ORDER_PORT}}"
INVENTORY_URL="${INVENTORY_URL:-http://127.0.0.1:${INVENTORY_PORT}}"
MGMT_URL="${MGMT_URL:-http://127.0.0.1:${MANAGEMENT_PORT}}"


mkdir -p "${RUN_DIR}" "${EVIDENCE_DIR}"

have_docker() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${ROOT_DIR}/docker-compose.yml" "$@"
  else
    docker-compose -f "${ROOT_DIR}/docker-compose.yml" "$@"
  fi
}

mode_file() {
  echo "${RUN_DIR}/mode"
}

detect_mode() {
  if [[ -f "$(mode_file)" ]]; then
    cat "$(mode_file)"
    return
  fi
  if have_docker && compose ps --status running 2>/dev/null | grep -q order-query; then
    echo docker
    return
  fi
  if [[ -f "${RUN_DIR}/order-query.pid" ]] && kill -0 "$(cat "${RUN_DIR}/order-query.pid")" 2>/dev/null; then
    echo local
    return
  fi
  echo unknown
}

wait_http() {
  local url="$1"
  local name="$2"
  local tries="${3:-60}"
  local i
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS --max-time 2 "${url}" >/dev/null 2>&1; then
      echo "[ok] ${name} ready: ${url}"
      return 0
    fi
    sleep 1
  done
  echo "[error] ${name} not ready after ${tries}s: ${url}" >&2
  return 1
}

order_container() {
  compose ps -q order-query
}

find_order_pid_local() {
  if [[ -f "${RUN_DIR}/order-query.pid" ]]; then
    local pid
    pid="$(cat "${RUN_DIR}/order-query.pid")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "${pid}"
      return 0
    fi
  fi
  jps -l 2>/dev/null | awk '/order-query|OrderQueryApplication/ {print $1; exit}'
}
