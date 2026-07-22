package com.terraformers.modernization.project;

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
import org.springframework.web.bind.annotation.DeleteMapping;
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
    private final AuthenticatedUserService authenticatedUserService;

    public ProjectMetadataController(
            ProjectMetadataService service,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.service = service;
        this.authenticatedUserService = authenticatedUserService;
    }

    @GetMapping
    public List<ProjectResponse> list(@AuthenticationPrincipal Jwt jwt) {
        return service.list(authenticatedUserService.getOrCreate(jwt));
    }

    @GetMapping("/public")
    public List<ProjectResponse> listPublic() {
        return service.listPublic();
    }

    @GetMapping("/{projectId}")
    public ProjectResponse get(
            @PathVariable Long projectId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        return service.get(projectId, optionalUser(jwt));
    }

    @DeleteMapping("/{projectId}")
    public ResponseEntity<Void> delete(
            @PathVariable Long projectId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        service.delete(projectId, authenticatedUserService.getOrCreate(jwt));
        return ResponseEntity.noContent().build();
    }

    @PatchMapping("/{projectId}/visibility")
    public ProjectResponse updateVisibility(
            @PathVariable Long projectId,
            @Valid @RequestBody ProjectVisibilityUpdateRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity currentUser = authenticatedUserService.getOrCreate(jwt);
        return service.updateVisibility(projectId, currentUser, request.visibility());
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

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBadRequest(IllegalArgumentException exception) {
        return ResponseEntity.badRequest().body(exception.getMessage());
    }

    private UserEntity optionalUser(Jwt jwt) {
        return jwt == null ? null : authenticatedUserService.getOrCreate(jwt);
    }
}
