package com.example.dogs;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/dogs")
public class DogController {

    private final DogRepository repository;

    public DogController(DogRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    public List<Dog> findAll() {
        return repository.findAll();
    }

    @GetMapping("/{dogId}")
    public ResponseEntity<Dog> findById(@PathVariable Long dogId) {
        return ResponseEntity.of(repository.findById(dogId));
    }

    @PostMapping
    public ResponseEntity<Dog> create(@RequestBody Dog dog) {
        dog.setId(null);
        return ResponseEntity.status(201).body(repository.save(dog));
    }

    @PutMapping("/{dogId}")
    public ResponseEntity<Dog> update(@PathVariable Long dogId, @RequestBody Dog dog) {
        if (!repository.existsById(dogId)) {
            return ResponseEntity.notFound().build();
        }
        dog.setId(dogId);
        return ResponseEntity.ok(repository.save(dog));
    }

    @DeleteMapping("/{dogId}")
    public ResponseEntity<Void> delete(@PathVariable Long dogId) {
        if (!repository.existsById(dogId)) {
            return ResponseEntity.notFound().build();
        }
        repository.deleteById(dogId);
        return ResponseEntity.noContent().build();
    }
}
