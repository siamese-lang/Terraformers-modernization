package com.terraformers.modernization.storage;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProjectSourceObjectController {

    private final SourceObjectReaderService service;
    private final AuthenticatedUserService authenticatedUserService;

    public ProjectSourceObjectController(
            SourceObjectReaderService service,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.service = service;
        this.authenticatedUserService = authenticatedUserService;
    }

    @GetMapping("/api/projects/{projectId}/source-object")
    public SourceObjectReadResponse readSourceObject(
            @PathVariable Long projectId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        return service.read(projectId, optionalUser(jwt));
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<String> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(exception.getMessage());
    }

    @ExceptionHandler(SecurityException.class)
    public ResponseEntity<String> handleForbidden(SecurityException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(exception.getMessage());
    }

    private UserEntity optionalUser(Jwt jwt) {
        return jwt == null ? null : authenticatedUserService.getOrCreate(jwt);
    }
}
