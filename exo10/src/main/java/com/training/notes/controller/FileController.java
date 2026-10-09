package com.training.notes.controller;

import com.training.notes.service.FileStorageService;
import com.training.notes.service.NoteService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/files")
@RequiredArgsConstructor
public class FileController {
    
    private final FileStorageService storageService;
    private final NoteService noteService;
    
    @PostMapping("/upload")
    public ResponseEntity<Map<String, Object>> upload(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "noteId", required = false) Long noteId) {
        try {
            String filename = storageService.store(file);
            
            if (noteId != null) {
                noteService.setAttachmentPath(noteId, filename);
            }
            
            Map<String, Object> response = new HashMap<>();
            response.put("filename", filename);
            response.put("originalName", file.getOriginalFilename());
            response.put("size", file.getSize());
            
            return ResponseEntity.ok(response);
        } catch (IOException e) {
            return ResponseEntity.internalServerError().build();
        }
    }
    
    @GetMapping("/download/{filename}")
    public ResponseEntity<byte[]> download(@PathVariable String filename) {
        try {
            byte[] data = storageService.load(filename);
            return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + filename + "\"")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(data);
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }
    
    @DeleteMapping("/{filename}")
    public ResponseEntity<Void> delete(@PathVariable String filename) {
        try {
            storageService.delete(filename);
            return ResponseEntity.noContent().build();
        } catch (IOException e) {
            return ResponseEntity.notFound().build();
        }
    }
    
    @GetMapping
    public ResponseEntity<List<String>> list() {
        try {
            return ResponseEntity.ok(storageService.listFiles());
        } catch (IOException e) {
            return ResponseEntity.internalServerError().build();
        }
    }
    
    @GetMapping("/info")
    public ResponseEntity<Map<String, Object>> info() {
        try {
            Map<String, Object> info = new HashMap<>();
            long usedBytes = storageService.getUsedSpace();
            info.put("usedBytes", usedBytes);
            info.put("usedMB", String.format("%.2f", usedBytes / (1024.0 * 1024.0)));
            info.put("fileCount", storageService.listFiles().size());
            return ResponseEntity.ok(info);
        } catch (IOException e) {
            return ResponseEntity.internalServerError().build();
        }
    }
}
