package com.terraformers.modernization.projectcomment;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import jakarta.validation.Valid;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProjectCommentController {

    private final ProjectCommentService service;
    private final AuthenticatedUserService authenticatedUserService;

    public ProjectCommentController(
            ProjectCommentService service,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.service = service;
        this.authenticatedUserService = authenticatedUserService;
    }

    @GetMapping("/api/projects/{projectId}/comments")
    public List<ProjectCommentResponse> listComments(@PathVariable Long projectId) {
        return service.listPublicProjectComments(projectId);
    }

    @PostMapping("/api/projects/{projectId}/comments")
    public ResponseEntity<ProjectCommentResponse> createComment(
            @PathVariable Long projectId,
            @Valid @RequestBody ProjectCommentCreateRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity currentUser = authenticatedUserService.getOrCreate(jwt);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(service.createPublicProjectComment(projectId, request, currentUser));
    }

    @GetMapping("/api/getProjectComments/{projectId}")
    public List<ProjectCommentResponse> listCommentsCompatibility(@PathVariable Long projectId) {
        return service.listPublicProjectComments(projectId);
    }

    @PostMapping("/api/addProjectComment")
    public ProjectCommentResponse createCommentCompatibility(
            @Valid @RequestBody ProjectCommentCompatibilityRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity currentUser = authenticatedUserService.getOrCreate(jwt);
        return service.createPublicProjectComment(request.projectId(), request.toCreateRequest(), currentUser);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<String> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(exception.getMessage());
    }

    @ExceptionHandler(SecurityException.class)
    public ResponseEntity<String> handleForbidden(SecurityException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(exception.getMessage());
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<String> handleUnauthorized(AuthenticationException exception) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(exception.getMessage());
    }
}
