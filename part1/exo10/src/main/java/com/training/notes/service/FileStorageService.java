package com.training.notes.service;

import com.training.notes.config.AppConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.*;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@RequiredArgsConstructor
@Slf4j
public class FileStorageService {
    
    private final AppConfig appConfig;
    private Path uploadPath;
    
    @PostConstruct
    public void init() {
        this.uploadPath = Paths.get(appConfig.getUploadPath());
        try {
            Files.createDirectories(uploadPath);
            log.info("Répertoire d'upload initialisé: {}", uploadPath.toAbsolutePath());
        } catch (IOException e) {
            throw new RuntimeException("Impossible de créer le répertoire d'upload", e);
        }
    }
    
    public String store(MultipartFile file) throws IOException {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("Fichier vide");
        }
        
        String originalName = file.getOriginalFilename();
        String extension = "";
        if (originalName != null && originalName.contains(".")) {
            extension = originalName.substring(originalName.lastIndexOf("."));
        }
        String newFilename = UUID.randomUUID() + extension;
        
        Path destination = uploadPath.resolve(newFilename);
        Files.copy(file.getInputStream(), destination, StandardCopyOption.REPLACE_EXISTING);
        
        log.info("Fichier uploadé: {} -> {}", originalName, newFilename);
        return newFilename;
    }
    
    public byte[] load(String filename) throws IOException {
        Path file = uploadPath.resolve(filename);
        if (!Files.exists(file)) {
            throw new RuntimeException("Fichier non trouvé: " + filename);
        }
        return Files.readAllBytes(file);
    }
    
    public void delete(String filename) throws IOException {
        Path file = uploadPath.resolve(filename);
        Files.deleteIfExists(file);
        log.info("Fichier supprimé: {}", filename);
    }
    
    public List<String> listFiles() throws IOException {
        try (Stream<Path> paths = Files.list(uploadPath)) {
            return paths
                .filter(Files::isRegularFile)
                .map(p -> p.getFileName().toString())
                .collect(Collectors.toList());
        }
    }
    
    public long getUsedSpace() throws IOException {
        try (Stream<Path> paths = Files.walk(uploadPath)) {
            return paths
                .filter(Files::isRegularFile)
                .mapToLong(p -> {
                    try { return Files.size(p); } 
                    catch (IOException e) { return 0; }
                })
                .sum();
        }
    }
}
