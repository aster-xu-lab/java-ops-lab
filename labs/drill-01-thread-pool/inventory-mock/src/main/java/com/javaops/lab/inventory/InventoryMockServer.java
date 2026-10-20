package com.javaops.lab.inventory;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

/**
 * 模拟变慢的库存 HTTP 服务：固定延迟后再返回，用来拖住 order-query 的工作线程。
 */
public final class InventoryMockServer {

    public static void main(String[] args) throws IOException {
        int port = intEnv("PORT", 8081);
        long delayMs = longEnv("DELAY_MS", 2500L);

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        // 下游本身并发要够，否则瓶颈会先出现在库存侧；本 Lab 要打满的是调用方线程池
        server.setExecutor(Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "inventory-worker");
            t.setDaemon(true);
            return t;
        }));

        server.createContext("/health", exchange -> writeJson(exchange, 200,
                "{\"status\":\"UP\",\"delayMs\":" + delayMs + "}"));

        server.createContext("/api/inventory/stock", exchange -> {
            if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
                writeJson(exchange, 405, "{\"error\":\"method not allowed\"}");
                return;
            }
            try {
                Thread.sleep(delayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                writeJson(exchange, 503, "{\"error\":\"interrupted\"}");
                return;
            }
            String sku = queryParam(exchange, "sku", "UNKNOWN");
            writeJson(exchange, 200,
                    "{\"sku\":\"" + sku + "\",\"available\":42,\"delayMs\":" + delayMs + "}");
        });

        server.start();
        System.out.printf("inventory-mock listening on :%d delayMs=%d%n", port, delayMs);
    }

    private static String queryParam(HttpExchange exchange, String key, String defaultValue) {
        String query = exchange.getRequestURI().getQuery();
        if (query == null || query.isBlank()) {
            return defaultValue;
        }
        for (String part : query.split("&")) {
            String[] kv = part.split("=", 2);
            if (kv.length == 2 && key.equals(kv[0])) {
                return kv[1];
            }
        }
        return defaultValue;
    }

    private static void writeJson(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static int intEnv(String name, int defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return Integer.parseInt(value.trim());
    }

    private static long longEnv(String name, long defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return Long.parseLong(value.trim());
    }
}
