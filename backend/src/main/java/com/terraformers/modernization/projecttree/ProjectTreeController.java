package com.terraformers.modernization.projecttree;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/project-tree")
public class ProjectTreeController {

    private final ProjectTreeService service;
    private final AuthenticatedUserService authenticatedUserService;

    public ProjectTreeController(
            ProjectTreeService service,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.service = service;
        this.authenticatedUserService = authenticatedUserService;
    }

    @GetMapping
    public List<ProjectTreeNode> listTrees(@AuthenticationPrincipal Jwt jwt) {
        return service.listTrees(authenticatedUserService.getOrCreate(jwt));
    }

    @GetMapping("/{projectId}")
    public ProjectTreeResponse getTree(
            @PathVariable Long projectId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        return service.getTree(projectId, optionalUser(jwt));
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

    private UserEntity optionalUser(Jwt jwt) {
        return jwt == null ? null : authenticatedUserService.getOrCreate(jwt);
    }
}
