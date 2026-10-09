package com.example.logs;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/logs")
public class LogController {

    private final LogRepository repository;

    public LogController(LogRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    public List<Log> findAll() {
        return repository.findAll();
    }

    @PostMapping
    public ResponseEntity<Log> create(@RequestBody Log log) {
        log.setId(null);
        return ResponseEntity.status(201).body(repository.save(log));
    }
}
