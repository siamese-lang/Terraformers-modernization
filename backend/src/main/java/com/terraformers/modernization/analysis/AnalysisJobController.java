package com.terraformers.modernization.analysis;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import jakarta.validation.Valid;
import java.net.URI;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/analysis/jobs")
public class AnalysisJobController {

    private final AnalysisJobService service;
    private final AuthenticatedUserService authenticatedUserService;

    public AnalysisJobController(
            AnalysisJobService service,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.service = service;
        this.authenticatedUserService = authenticatedUserService;
    }

    @PostMapping
    public ResponseEntity<AnalysisJobResponse> create(
            @Valid @RequestBody AnalysisJobRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity requester = authenticatedUserService.getOrCreate(jwt);
        AnalysisJobResponse response = service.create(request, requester);
        return ResponseEntity
                .created(URI.create("/api/analysis/jobs/" + response.id()))
                .body(response);
    }

    @GetMapping("/{id}")
    public AnalysisJobResponse get(
            @PathVariable String id,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity requester = authenticatedUserService.getOrCreate(jwt);
        return service.get(id, requester);
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
}
