package com.training.notes.repository;

import com.training.notes.model.Note;
import com.training.notes.model.Note.Priority;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface NoteRepository extends JpaRepository<Note, Long> {
    
    List<Note> findByCategory(String category);
    
    List<Note> findByPriority(Priority priority);
    
    @Query("SELECT n FROM Note n WHERE LOWER(n.title) LIKE LOWER(CONCAT('%',:q,'%')) OR LOWER(n.content) LIKE LOWER(CONCAT('%',:q,'%'))")
    List<Note> search(String q);
}
