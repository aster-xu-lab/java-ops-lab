# java-ops-lab

Java 运维 / 线上排查可动手实验室。

## Labs

| Lab | 说明 |
|-----|------|
| [labs/drill-01-thread-pool](./labs/drill-01-thread-pool/) | 演练 01：慢下游把 Tomcat 工作线程打满，本地一键复现 + jstack |

快速开始：

```bash
cd labs/drill-01-thread-pool
./scripts/reproduce.sh
./scripts/cleanup.sh
```
