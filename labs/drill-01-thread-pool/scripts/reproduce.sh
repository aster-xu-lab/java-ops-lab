#!/usr/bin/env bash
# 一键最短复现：启动 → 后台压测 → 抓 jstack → 打印预期现象摘要
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

MODE_ARG="${1:-auto}"

"${SCRIPT_DIR}/start.sh" "${MODE_ARG}"

echo
echo "[info] 后台压测 25s（并发 30）..."
"${SCRIPT_DIR}/load.sh" 30 25 &
LOAD_PID=$!

# 等线程打满后再抓栈
sleep 8
"${SCRIPT_DIR}/jstack.sh" 2 5

wait "${LOAD_PID}" || true

echo
echo "======== 复现完成：预期现象 ========"
echo "1) CPU 不必很高，但 /api/order/detail 变慢（秒级）"
echo "2) tomcat.threads.busy 接近 max(=10)"
echo "3) jstack 中大量 http-nio-*-exec-* 处于 TIMED_WAITING/WAITING，栈含 socketRead / RestTemplate"
echo "4) RUNNABLE 很少 → 阻塞型打满，不是算力热点"
echo
echo "证据目录: ${EVIDENCE_DIR}/"
echo "清理: ${SCRIPT_DIR}/cleanup.sh"
