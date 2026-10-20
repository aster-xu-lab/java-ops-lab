package com.javaops.lab.order;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/order")
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);

    private final RestTemplate inventoryRestTemplate;

    public OrderController(RestTemplate inventoryRestTemplate) {
        this.inventoryRestTemplate = inventoryRestTemplate;
    }

    /**
     * 对齐演练文档中的 /api/order/detail：同步调用慢库存，占用 Tomcat worker。
     */
    @GetMapping("/detail")
    public ResponseEntity<Map<String, Object>> detail(@RequestParam(defaultValue = "ORD-1001") String orderId) {
        long started = System.currentTimeMillis();
        String sku = "SKU-" + orderId;

        Map<String, Object> stock;
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = inventoryRestTemplate.getForObject(
                    "/api/inventory/stock?sku={sku}", Map.class, sku);
            stock = body == null ? Map.of() : body;
        } catch (RestClientException ex) {
            log.warn("inventory call failed orderId={} err={}", orderId, ex.toString());
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("orderId", orderId);
            err.put("error", "inventory_timeout_or_unavailable");
            err.put("message", ex.getMessage());
            err.put("elapsedMs", System.currentTimeMillis() - started);
            return ResponseEntity.status(504).body(err);
        }

        Map<String, Object> ok = new LinkedHashMap<>();
        ok.put("orderId", orderId);
        ok.put("status", "PAID");
        ok.put("sku", sku);
        ok.put("inventory", stock);
        ok.put("elapsedMs", System.currentTimeMillis() - started);
        return ResponseEntity.ok(ok);
    }
}
