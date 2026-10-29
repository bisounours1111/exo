package com.training.notes.controller;

import com.training.notes.config.AppConfig;
import lombok.RequiredArgsConstructor;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/info")
@RequiredArgsConstructor
public class InfoController {
    
    private final AppConfig appConfig;
    private final Environment env;
    private final DataSource dataSource;
    
    @GetMapping("/app")
    public Map<String, Object> getAppInfo() {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("name", appConfig.getName());
        info.put("version", appConfig.getVersion());
        info.put("environment", appConfig.getEnvironment());
        info.put("uploadPath", appConfig.getUploadPath());
        return info;
    }
    
    @GetMapping("/env")
    public Map<String, String> getEnvVariables() {
        Map<String, String> envVars = new LinkedHashMap<>();
        
        String[] vars = {
            "APP_NAME", "APP_VERSION", "APP_ENV",
            "DB_HOST", "DB_PORT", "DB_NAME", "DB_USER",
            "UPLOAD_PATH", "MAX_FILE_SIZE",
            "LOG_LEVEL", "SHOW_SQL"
        };
        
        for (String var : vars) {
            String value = env.getProperty(var);
            if (value != null) {
                if (var.contains("PASSWORD")) {
                    value = "********";
                }
                envVars.put(var, value);
            }
        }
        
        return envVars;
    }
    
    @GetMapping("/health")
    public Map<String, Object> getHealth() {
        Map<String, Object> health = new LinkedHashMap<>();
        health.put("application", "UP");
        
        try (Connection conn = dataSource.getConnection()) {
            health.put("database", "UP");
            health.put("dbProduct", conn.getMetaData().getDatabaseProductName());
        } catch (Exception e) {
            health.put("database", "DOWN");
            health.put("dbError", e.getMessage());
        }
        
        return health;
    }
}
