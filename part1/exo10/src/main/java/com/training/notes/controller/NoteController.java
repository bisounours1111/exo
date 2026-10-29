package com.training.notes.controller;

import com.training.notes.model.Note;
import com.training.notes.model.Note.Priority;
import com.training.notes.service.NoteService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/notes")
@RequiredArgsConstructor
public class NoteController {
    
    private final NoteService noteService;
    
    @GetMapping
    public List<Note> getAll() {
        return noteService.findAll();
    }
    
    @GetMapping("/{id}")
    public ResponseEntity<Note> getById(@PathVariable Long id) {
        return noteService.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }
    
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Note create(@Valid @RequestBody Note note) {
        return noteService.create(note);
    }
    
    @PutMapping("/{id}")
    public ResponseEntity<Note> update(@PathVariable Long id, @Valid @RequestBody Note note) {
        try {
            return ResponseEntity.ok(noteService.update(id, note));
        } catch (RuntimeException e) {
            return ResponseEntity.notFound().build();
        }
    }
    
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        noteService.delete(id);
    }
    
    @GetMapping("/category/{category}")
    public List<Note> getByCategory(@PathVariable String category) {
        return noteService.findByCategory(category);
    }
    
    @GetMapping("/priority/{priority}")
    public List<Note> getByPriority(@PathVariable Priority priority) {
        return noteService.findByPriority(priority);
    }
    
    @GetMapping("/search")
    public List<Note> search(@RequestParam String q) {
        return noteService.search(q);
    }
}
