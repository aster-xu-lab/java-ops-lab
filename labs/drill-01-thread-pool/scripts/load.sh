#!/usr/bin/env bash
# 压测打满 Tomcat 工作线程（默认并发 30，持续约 20s）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

CONCURRENCY="${1:-30}"
DURATION_SEC="${2:-20}"
URL="${ORDER_URL}/api/order/detail?orderId=LOAD"

echo "[info] 压测目标: ${URL}"
echo "[info] 并发=${CONCURRENCY} 持续=${DURATION_SEC}s"
echo "[info] Tomcat max threads=10，库存 delay≈2.5s → 预期 busy≈max，新请求排队变慢"
echo

end_at=$((SECONDS + DURATION_SEC))
stat_dir="${RUN_DIR}/load-stats.$$"
mkdir -p "${stat_dir}"
pids=()

worker() {
  local id="$1"
  local ok=0 fail=0
  while (( SECONDS < end_at )); do
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      "${URL}&n=${id}-${RANDOM}" || true)"
    if [[ "${code}" == "200" ]]; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done
  echo "${ok}" >"${stat_dir}/ok.${id}"
  echo "${fail}" >"${stat_dir}/fail.${id}"
}

for ((i = 1; i <= CONCURRENCY; i++)); do
  worker "$i" &
  pids+=($!)
done

# 压测期间从管理端口抽样 busy（不占用业务线程池）
sleep 3
echo "--- 压测中抽样指标（management :${MANAGEMENT_PORT}）---"
curl -fsS --max-time 2 "${MGMT_URL}/actuator/metrics/tomcat.threads.busy" 2>/dev/null \
  | tee "${EVIDENCE_DIR}/tomcat-threads-busy.json" | head -c 500 \
  || echo "(busy metrics 暂不可用)"
echo
curl -fsS --max-time 2 "${MGMT_URL}/actuator/metrics/tomcat.threads.current" 2>/dev/null \
  | tee "${EVIDENCE_DIR}/tomcat-threads-current.json" | head -c 500 || true
echo
echo "--- 继续压测至结束 ---"

for pid in "${pids[@]}"; do
  wait "${pid}" || true
done

ok=0
fail=0
for f in "${stat_dir}"/ok.*; do
  [[ -f "${f}" ]] || continue
  ok=$((ok + $(cat "${f}")))
done
for f in "${stat_dir}"/fail.*; do
  [[ -f "${f}" ]] || continue
  fail=$((fail + $(cat "${f}")))
done
rm -rf "${stat_dir}"

echo
echo "[done] 压测结束 ok=${ok} fail_or_non200=${fail}"
echo "下一步: ./scripts/jstack.sh   # 在压测进行中另开终端抓栈效果更好"

