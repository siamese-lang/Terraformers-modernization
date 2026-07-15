package com.terraformers.modernization.project;

import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProjectTreeController {

    private final ProjectMetadataService projectMetadataService;

    public ProjectTreeController(ProjectMetadataService projectMetadataService) {
        this.projectMetadataService = projectMetadataService;
    }

    @GetMapping("/api/project-tree/{projectId}")
    public ProjectTreeResponse getProjectTree(@PathVariable String projectId) {
        return ProjectTreeResponse.from(projectMetadataService.get(projectId));
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
