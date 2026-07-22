package com.terraformers.modernization.identity;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class UserProfileController {
    private final AuthenticatedUserService authenticatedUserService;

    public UserProfileController(AuthenticatedUserService authenticatedUserService) {
        this.authenticatedUserService = authenticatedUserService;
    }

    @PatchMapping("/api/users/me/display-name")
    public ResponseEntity<Void> updateDisplayName(
            @Valid @RequestBody DisplayNameUpdateRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {
        authenticatedUserService.updateCurrentDisplayName(jwt, request.displayName());
        return ResponseEntity.noContent().build();
    }
}
