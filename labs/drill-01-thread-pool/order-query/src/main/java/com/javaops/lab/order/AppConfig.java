package com.javaops.lab.order;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
@EnableConfigurationProperties(InventoryProperties.class)
public class AppConfig {

    @Bean
    RestTemplate inventoryRestTemplate(RestTemplateBuilder builder, InventoryProperties props) {
        return builder
                .rootUri(props.getBaseUrl())
                .setConnectTimeout(props.getConnectTimeout())
                .setReadTimeout(props.getReadTimeout())
                .build();
    }
}
