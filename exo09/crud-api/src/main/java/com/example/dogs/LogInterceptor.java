package com.example.dogs;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class LogInterceptor implements HandlerInterceptor {

    private final LogClient logClient;

    public LogInterceptor(LogClient logClient) {
        this.logClient = logClient;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        int status = response.getStatus();
        String source = "[CrudAPI] " + request.getMethod() + " " + request.getRequestURI();

        String level;
        if (ex != null || status >= 500) {
            level = "ERR";
        } else if (status >= 400) {
            level = "WARN";
        } else {
            level = "INFO";
        }

        HttpStatus httpStatus = HttpStatus.resolve(status);
        String message = status + " " + (httpStatus != null ? httpStatus.getReasonPhrase() : "");
        if (ex != null) {
            message += " : " + ex.getMessage();
        }

        logClient.send(message, source, level);
    }
}
