package com.training.notes.service;

import com.training.notes.model.Note;
import com.training.notes.model.Note.Priority;
import com.training.notes.repository.NoteRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class NoteService {
    
    private final NoteRepository noteRepository;
    
    public List<Note> findAll() {
        return noteRepository.findAll();
    }
    
    public Optional<Note> findById(Long id) {
        return noteRepository.findById(id);
    }
    
    public Note create(Note note) {
        Note saved = noteRepository.save(note);
        log.info("Note créée: {} (ID: {})", saved.getTitle(), saved.getId());
        return saved;
    }
    
    public Note update(Long id, Note noteDetails) {
        return noteRepository.findById(id)
            .map(note -> {
                note.setTitle(noteDetails.getTitle());
                note.setContent(noteDetails.getContent());
                note.setCategory(noteDetails.getCategory());
                note.setPriority(noteDetails.getPriority());
                Note updated = noteRepository.save(note);
                log.info("Note mise à jour: {} (ID: {})", updated.getTitle(), id);
                return updated;
            })
            .orElseThrow(() -> new RuntimeException("Note non trouvée: " + id));
    }
    
    public void delete(Long id) {
        noteRepository.deleteById(id);
        log.info("Note supprimée (ID: {})", id);
    }
    
    public List<Note> findByCategory(String category) {
        return noteRepository.findByCategory(category);
    }
    
    public List<Note> findByPriority(Priority priority) {
        return noteRepository.findByPriority(priority);
    }
    
    public List<Note> search(String q) {
        return noteRepository.search(q);
    }
    
    public void setAttachmentPath(Long id, String path) {
        noteRepository.findById(id).ifPresent(note -> {
            note.setAttachmentPath(path);
            noteRepository.save(note);
        });
    }
}
