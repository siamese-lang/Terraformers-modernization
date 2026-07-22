package com.terraformers.modernization.project;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import jakarta.validation.Valid;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/projects/{projectId}/terraform")
public class TerraformDraftController {

    private final ProjectMetadataService projectMetadataService;
    private final AuthenticatedUserService authenticatedUserService;

    public TerraformDraftController(
            ProjectMetadataService projectMetadataService,
            AuthenticatedUserService authenticatedUserService
    ) {
        this.projectMetadataService = projectMetadataService;
        this.authenticatedUserService = authenticatedUserService;
    }

    @GetMapping("/main.tf")
    public TerraformDraftResponse getMainTf(
            @PathVariable Long projectId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        return projectMetadataService.getTerraformDraft(projectId, optionalUser(jwt));
    }

    @PutMapping("/main.tf")
    public TerraformDraftResponse updateMainTf(
            @PathVariable Long projectId,
            @Valid @RequestBody TerraformDraftUpdateRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        UserEntity currentUser = authenticatedUserService.getOrCreate(jwt);
        return projectMetadataService.updateTerraformDraft(projectId, currentUser, request.content());
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
