package com.terraformers.modernization.projectcomment;

import jakarta.validation.Valid;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProjectCommentController {

    private final ProjectCommentService service;

    public ProjectCommentController(ProjectCommentService service) {
        this.service = service;
    }

    @GetMapping("/api/projects/{projectId}/comments")
    public List<ProjectCommentResponse> listComments(@PathVariable String projectId) {
        return service.listPublicProjectComments(projectId);
    }

    @PostMapping("/api/projects/{projectId}/comments")
    public ResponseEntity<ProjectCommentResponse> createComment(
            @PathVariable String projectId,
            @Valid @RequestBody ProjectCommentCreateRequest request
    ) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(service.createPublicProjectComment(projectId, request));
    }

    @GetMapping("/api/getProjectComments/{projectId}")
    public List<ProjectCommentResponse> listCommentsCompatibility(@PathVariable String projectId) {
        return service.listPublicProjectComments(projectId);
    }

    @PostMapping("/api/addProjectComment")
    public ProjectCommentResponse createCommentCompatibility(
            @Valid @RequestBody ProjectCommentCompatibilityRequest request
    ) {
        return service.createPublicProjectComment(request.projectId(), request.toCreateRequest());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
