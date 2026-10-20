#!/usr/bin/env bash
# 抓取 order-query 线程 dump（默认 2 次，间隔 5s），并对齐演练文档做状态统计
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

COUNT="${1:-2}"
INTERVAL="${2:-5}"
TS="$(date +%Y%m%d-%H%M%S)"
MODE="$(detect_mode)"

dump_once() {
  local idx="$1"
  local out="${EVIDENCE_DIR}/jstack-${TS}-${idx}.txt"
  case "${MODE}" in
    docker)
      local cid
      cid="$(order_container)"
      [[ -n "${cid}" ]] || { echo "找不到 order-query 容器，请先 ./scripts/start.sh" >&2; exit 1; }
      # 容器内 JDK 镜像带 jcmd/jstack
      docker exec "${cid}" bash -lc '
        pid=$(jps -l | awk "/order-query|app.jar|OrderQuery/ {print \$1; exit}")
        if [[ -z "$pid" ]]; then pid=1; fi
        if command -v jstack >/dev/null; then
          jstack "$pid"
        else
          jcmd "$pid" Thread.print
        fi
      ' >"${out}"
      ;;
    local)
      local pid
      pid="$(find_order_pid_local || true)"
      [[ -n "${pid}" ]] || { echo "找不到本地 order-query PID，请先 ./scripts/start.sh" >&2; exit 1; }
      if command -v jstack >/dev/null; then
        jstack "${pid}" >"${out}"
      else
        jcmd "${pid}" Thread.print >"${out}"
      fi
      ;;
    *)
      echo "服务未运行或模式未知。请先: ./scripts/start.sh" >&2
      exit 1
      ;;
  esac
  echo "[ok] wrote ${out}" >&2
  # 仅把路径打到 stdout，供调用方收集
  printf '%s\n' "${out}"
}

echo "[info] mode=${MODE} dumps=${COUNT} interval=${INTERVAL}s"
files=()
for ((i = 1; i <= COUNT; i++)); do
  files+=("$(dump_once "$i")")
  if (( i < COUNT )); then
    sleep "${INTERVAL}"
  fi
done

echo
echo "======== 线程状态分布（对齐演练 Step 2）========"
grep 'java.lang.Thread.State' "${files[@]}" | sort | uniq -c | sort -rn || true

echo
echo "======== http-nio exec 线程名（去重）========"
grep -E '^"http-nio-.*-exec-' "${files[@]}" | sort -u || true

echo
echo "======== 常见阻塞点关键词（节选）========"
grep -E 'Net\.poll|socketRead|HttpClient|RestTemplate|NioSocketImpl|park' "${files[0]}" | head -50 || true

echo
echo "完整 dump 已写入 ${EVIDENCE_DIR}/"
echo "可选 Actuator: curl -s ${MGMT_URL}/actuator/threaddump | head"
echo "busy 指标:     curl -s ${MGMT_URL}/actuator/metrics/tomcat.threads.busy"

