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
echo "2) ${MGMT_URL}/actuator/metrics/tomcat.threads.busy 接近 max(=10)"
echo "3) jstack：约 10 条 http-nio-8080-exec-*，栈含 RestTemplate / NioSocketImpl / Net.poll"
echo "4) 现代 JDK 上阻塞读常显示 RUNNABLE(native)，关键看栈与 busy，不是 CPU 热点循环"
echo
echo "证据目录: ${EVIDENCE_DIR}/"
echo "清理: ${SCRIPT_DIR}/cleanup.sh"
