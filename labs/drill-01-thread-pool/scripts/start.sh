#!/usr/bin/env bash
# 启动 inventory-mock + order-query（Docker Compose 优先，否则本地 jar）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

MODE="${1:-auto}"

start_docker() {
  echo "[info] 使用 Docker Compose 启动..."
  compose up -d --build
  echo docker >"$(mode_file)"
  wait_http "${INVENTORY_URL}/health" "inventory-mock" 90
  wait_http "${MGMT_URL}/actuator/health" "order-query-mgmt" 90
  echo
  echo "已启动（docker）："
  echo "  订单查询: ${ORDER_URL}/api/order/detail?orderId=ORD-1001"
  echo "  库存模拟: ${INVENTORY_URL}/health"
  echo "  Actuator : ${MGMT_URL}/actuator/metrics/tomcat.threads.busy"
}

start_local() {
  echo "[info] 使用本地 Java 进程启动（无 Docker）..."
  command -v mvn >/dev/null || { echo "需要 Maven (mvn)" >&2; exit 1; }
  command -v java >/dev/null || { echo "需要 Java 21+" >&2; exit 1; }

  if [[ ! -f "${ROOT_DIR}/inventory-mock/target/inventory-mock-1.0.0.jar" ]]; then
    echo "[info] 构建 inventory-mock..."
    (cd "${ROOT_DIR}/inventory-mock" && mvn -q -DskipTests package)
  fi
  if [[ ! -f "${ROOT_DIR}/order-query/target/order-query-1.0.0.jar" ]]; then
    echo "[info] 构建 order-query..."
    (cd "${ROOT_DIR}/order-query" && mvn -q -DskipTests package)
  fi

  # 清理残留
  if [[ -f "${RUN_DIR}/inventory.pid" ]]; then
    kill "$(cat "${RUN_DIR}/inventory.pid")" 2>/dev/null || true
  fi
  if [[ -f "${RUN_DIR}/order-query.pid" ]]; then
    kill "$(cat "${RUN_DIR}/order-query.pid")" 2>/dev/null || true
  fi

  PORT="${INVENTORY_PORT}" DELAY_MS="${DELAY_MS:-2500}" \
    java -jar "${ROOT_DIR}/inventory-mock/target/inventory-mock-1.0.0.jar" \
    >"${RUN_DIR}/inventory.log" 2>&1 &
  echo $! >"${RUN_DIR}/inventory.pid"

  PORT="${ORDER_PORT}" MANAGEMENT_PORT="${MANAGEMENT_PORT}" \
    INVENTORY_BASE_URL="http://127.0.0.1:${INVENTORY_PORT}" \
    java -jar "${ROOT_DIR}/order-query/target/order-query-1.0.0.jar" \
    >"${RUN_DIR}/order-query.log" 2>&1 &
  echo $! >"${RUN_DIR}/order-query.pid"

  echo local >"$(mode_file)"
  wait_http "${INVENTORY_URL}/health" "inventory-mock" 60
  wait_http "${MGMT_URL}/actuator/health" "order-query-mgmt" 90
  echo
  echo "已启动（local）："
  echo "  inventory pid=$(cat "${RUN_DIR}/inventory.pid")  log=${RUN_DIR}/inventory.log"
  echo "  order-query pid=$(cat "${RUN_DIR}/order-query.pid")  log=${RUN_DIR}/order-query.log"
  echo "  试调用: curl '${ORDER_URL}/api/order/detail?orderId=ORD-1001'"
  echo "  指标:   curl '${MGMT_URL}/actuator/metrics/tomcat.threads.busy'"
}

case "${MODE}" in
  docker)
    have_docker || { echo "Docker 不可用" >&2; exit 1; }
    start_docker
    ;;
  local)
    start_local
    ;;
  auto|"")
    if have_docker; then
      start_docker
    else
      echo "[warn] 未检测到可用 Docker，回退本地模式"
      start_local
    fi
    ;;
  *)
    echo "用法: $0 [auto|docker|local]" >&2
    exit 1
    ;;
esac
