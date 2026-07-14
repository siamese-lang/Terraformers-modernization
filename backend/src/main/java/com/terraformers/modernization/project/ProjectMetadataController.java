package com.terraformers.modernization.project;

import jakarta.validation.Valid;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/projects")
public class ProjectMetadataController {

    private final ProjectMetadataService service;

    public ProjectMetadataController(ProjectMetadataService service) {
        this.service = service;
    }

    @GetMapping
    public List<ProjectResponse> list() {
        return service.list();
    }

    @GetMapping("/public")
    public List<ProjectResponse> listPublic() {
        return service.listPublic();
    }

    @GetMapping("/{projectId}")
    public ProjectResponse get(@PathVariable String projectId) {
        return service.get(projectId);
    }

    @PatchMapping("/{projectId}/visibility")
    public ProjectResponse updateVisibility(
            @PathVariable String projectId,
            @Valid @RequestBody ProjectVisibilityUpdateRequest request
    ) {
        return service.updateVisibility(projectId, request.visibility());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
