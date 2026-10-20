# Lab：演练 01 — 线程池打满（可本地复现）

对齐 Project 文档：`docs/prod-troubleshooting-drill-01.md`（线上排查演练 01：高峰期接口超时 / 线程池打满）。

本目录提供**最小可运行**环境：Spring Boot `order-query` + 故意变慢的 `inventory-mock`，用压测把 Tomcat 工作线程打满，再抓 `jstack` 对照演练预期栈。

---

## 架构（刻意简化）

| 组件 | 作用 |
|------|------|
| `order-query` (:8080) | Spring Boot + Tomcat，`server.tomcat.threads.max=10`，同步 HTTP 调库存 |
| Actuator (:8082) | 独立管理端口，饱和时仍可看 `tomcat.threads.busy` |
| `inventory-mock` (:8081) | JDK `HttpServer`，每个请求 `sleep ~2500ms` 再返回 |

主线与演练一致：**慢下游占满工作线程 → 队列堆积 → 新请求变慢/超时**；CPU 不必很高。

未引入真实 DB/Redis/Hikari，避免干扰「线程池打满」这一条主线。

---

## 最短复现（推荐）

依赖：Docker + Compose（优先），或本地 **JDK 21 + Maven**。

```bash
cd labs/drill-01-thread-pool

# 一键：启动 → 压测 → 抓 2 次 jstack
./scripts/reproduce.sh

# 结束后清理
./scripts/cleanup.sh
```

分步：

```bash
./scripts/start.sh          # auto：有 Docker 用 Compose，否则本地 jar
./scripts/load.sh 30 20     # 并发 30，持续 20s（建议另开终端同时 jstack）
./scripts/jstack.sh         # 默认打 2 次，间隔 5s，输出到 evidence/
./scripts/cleanup.sh
```

强制模式：

```bash
./scripts/start.sh docker
./scripts/start.sh local
```

纯 Compose（不用脚本也行）：

```bash
docker compose up -d --build
# 压测示例
for i in $(seq 1 30); do curl -s -o /dev/null -w '%{http_code}\n' \
  --max-time 15 'http://127.0.0.1:8080/api/order/detail?orderId=LOAD' & done; wait
docker compose exec order-query bash -lc 'jstack $(jps -l | awk "/app.jar/{print \$1;exit}")'
docker compose down
```

---

## 预期现象（对齐演练文档）

1. **接口变慢**：`/api/order/detail` 单次约 ≥2.5s（库存 sleep）；并发上来后排队，体感到秒级 P99。  
2. **CPU 不必爆**：本机负载可中等，重点是阻塞而非算力。  
3. **线程打满**（管理端口 **8082**，不占用业务线程池）：  
   - `curl -s localhost:8082/actuator/metrics/tomcat.threads.busy` 中 `VALUE` 接近 **10**  
   - 同时 `tomcat.threads.current` 也贴近 max  
4. **jstack 典型栈**（`evidence/jstack-*.txt`）：  
   - 约 10 条 `http-nio-*-exec-*`，栈经 `RestTemplate` → `HttpURLConnection` → `NioSocketImpl` / `Net.poll`  
   - 现代 JDK 上阻塞读 socket **常显示为 `RUNNABLE`（native poll）**，不要只按 `TIMED_WAITING` 过滤；关键是栈顶在等下游响应，且线程 busy≈max  
   - 业务代码没有吃满 CPU 的热点循环  
5. 可用演练同款统计：

```bash
grep 'java.lang.Thread.State' evidence/jstack-*.txt | sort | uniq -c | sort -rn
grep -E 'RestTemplate|NioSocketImpl|Net\.poll|HttpClient' evidence/jstack-*.txt | head -50
```

可选：`GET http://localhost:8082/actuator/threaddump` 与 `jstack` 对照。

---

## 目录说明

```text
labs/drill-01-thread-pool/
  docker-compose.yml
  README.md                 # 本文件
  scripts/                  # start / load / jstack / cleanup / reproduce
  order-query/              # Spring Boot 订单查询
  inventory-mock/           # 慢库存模拟
  evidence/                 # jstack 输出（运行生成）
  .run/                     # 本地 pid/日志（运行生成，勿提交）
```

---

## 与演练文档的对应关系

| 演练要点 | 本 Lab |
|----------|--------|
| `/api/order/detail` 超时/变慢 | 同路径，同步调慢库存 |
| CPU 不高 + 延迟高 | sleep IO，无重计算 |
| jstack 看工作线程堵在读下游 | Tomcat `http-nio-*-exec-*` + RestTemplate |
| 止血：缩短超时 / 降级 / 限流 | 可自行改 `inventory.read-timeout` 或砍库存调用做对比实验 |
| Hikari / 慢 SQL | 本 Lab 刻意省略；口述时仍按演练文档展开 |

---

## 常见问题

- **首次 `start.sh local` 较慢**：Maven 拉 Spring Boot 依赖。  
- **压测时 metrics 也卡住**：说明线程已饱和，属预期；用已在跑的 `jstack` / 事先打开的指标即可。  
- **容器内无 jstack**：`order-query` 镜像基于 JDK（非 JRE），脚本走 `jstack`/`jcmd`。  
- **端口占用**：改环境变量 `ORDER_PORT` / `INVENTORY_PORT` 后重新 `start.sh local`。
