FROM eclipse-temurin:21-jdk-jammy AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN apt-get update && apt-get install -y --no-install-recommends maven \
    && mvn -q -DskipTests package \
    && apt-get purge -y maven && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=build /src/target/inventory-mock-1.0.0.jar /app/app.jar
ENV PORT=8081 DELAY_MS=2500
EXPOSE 8081
CMD ["java", "-jar", "/app/app.jar"]
