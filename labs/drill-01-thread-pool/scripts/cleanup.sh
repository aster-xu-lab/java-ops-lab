#!/usr/bin/env bash
# 停止并清理本 Lab 进程 / 容器
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

MODE="$(detect_mode)"
echo "[info] cleanup mode=${MODE}"

if have_docker; then
  compose down --remove-orphans 2>/dev/null || true
fi

if [[ -f "${RUN_DIR}/order-query.pid" ]]; then
  kill "$(cat "${RUN_DIR}/order-query.pid")" 2>/dev/null || true
  rm -f "${RUN_DIR}/order-query.pid"
fi
if [[ -f "${RUN_DIR}/inventory.pid" ]]; then
  kill "$(cat "${RUN_DIR}/inventory.pid")" 2>/dev/null || true
  rm -f "${RUN_DIR}/inventory.pid"
fi

# 兜底：按 jar 名杀残留
pkill -f 'inventory-mock-1.0.0.jar' 2>/dev/null || true
pkill -f 'order-query-1.0.0.jar' 2>/dev/null || true

rm -f "$(mode_file)"
echo "[ok] 已清理。日志仍保留在 ${RUN_DIR}/ ，证据在 ${EVIDENCE_DIR}/"
echo "如需连构建产物一起删: rm -rf ${ROOT_DIR}/inventory-mock/target ${ROOT_DIR}/order-query/target ${RUN_DIR}"
