FROM eclipse-temurin:21-jdk-jammy AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN apt-get update && apt-get install -y --no-install-recommends maven \
    && mvn -q -DskipTests package \
    && apt-get purge -y maven && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

FROM eclipse-temurin:21-jdk-jammy
# 使用 JDK 镜像以便容器内可执行 jstack / jcmd
WORKDIR /app
COPY --from=build /src/target/order-query-1.0.0.jar /app/app.jar
ENV PORT=8080 \
    MANAGEMENT_PORT=8082 \
    INVENTORY_BASE_URL=http://inventory-mock:8081
EXPOSE 8080 8082
CMD ["java", "-jar", "/app/app.jar"]
