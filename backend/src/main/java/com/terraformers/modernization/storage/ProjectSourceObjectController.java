package com.terraformers.modernization.storage;

import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProjectSourceObjectController {

    private final SourceObjectReaderService service;

    public ProjectSourceObjectController(SourceObjectReaderService service) {
        this.service = service;
    }

    @GetMapping("/api/projects/{projectId}/source-object")
    public SourceObjectReadResponse readSourceObject(@PathVariable String projectId) {
        return service.read(projectId);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
