package com.example.dogs;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.Map;

@Component
public class LogClient {

    private final RestTemplate restTemplate = new RestTemplate();

    @Value("${logs.url}")
    private String logsUrl;

    public void send(String message, String source, String level) {
        Map<String, String> log = Map.of(
                "message", message,
                "source", source,
                "timestamp", Instant.now().toString(),
                "level", level
        );
        try {
            restTemplate.postForObject(logsUrl, log, Void.class);
        } catch (Exception e) {
            System.err.println("Impossible d'envoyer le log : " + e.getMessage());
        }
    }
}
