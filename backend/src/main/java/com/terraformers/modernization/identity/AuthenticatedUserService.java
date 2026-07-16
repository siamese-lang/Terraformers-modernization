package com.terraformers.modernization.identity;

import java.util.Locale;
import java.util.Objects;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthenticatedUserService {

    private final UserRepository userRepository;

    public AuthenticatedUserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Transactional
    public UserEntity getOrCreate(Jwt jwt) {
        if (jwt == null) {
            throw new AuthenticationCredentialsNotFoundException("authenticated Cognito JWT is required");
        }

        String cognitoSub = requiredClaim(jwt, "sub", 128);
        String email = requiredClaim(jwt, "email", 320).toLowerCase(Locale.ROOT);
        String displayName = resolveDisplayName(jwt, email);

        return userRepository.findByCognitoSub(cognitoSub)
                .map(existing -> synchronize(existing, email, displayName))
                .orElseGet(() -> createWithRetry(cognitoSub, email, displayName));
    }

    private UserEntity synchronize(UserEntity existing, String email, String displayName) {
        userRepository.findByEmail(email)
                .filter(other -> !Objects.equals(other.getUserId(), existing.getUserId()))
                .ifPresent(other -> {
                    throw new IllegalStateException("authenticated email is already linked to another user");
                });

        boolean changed = false;
        if (!email.equals(existing.getEmail())) {
            existing.setEmail(email);
            changed = true;
        }
        if (!Objects.equals(displayName, existing.getDisplayName())) {
            existing.setDisplayName(displayName);
            changed = true;
        }
        if (existing.getStatus() != UserStatus.ACTIVE) {
            throw new IllegalStateException("authenticated user is not active");
        }
        return changed ? userRepository.save(existing) : existing;
    }

    private UserEntity createWithRetry(String cognitoSub, String email, String displayName) {
        userRepository.findByEmail(email).ifPresent(existing -> {
            throw new IllegalStateException("authenticated email is already linked to another Cognito subject");
        });

        UserEntity user = new UserEntity();
        user.setCognitoSub(cognitoSub);
        user.setEmail(email);
        user.setDisplayName(displayName);
        user.setRole(UserRole.USER);
        user.setStatus(UserStatus.ACTIVE);

        try {
            return userRepository.save(user);
        } catch (DataIntegrityViolationException exception) {
            return userRepository.findByCognitoSub(cognitoSub)
                    .map(existing -> synchronize(existing, email, displayName))
                    .orElseThrow(() -> exception);
        }
    }

    private String resolveDisplayName(Jwt jwt, String email) {
        String displayName = firstNonBlank(
                jwt.getClaimAsString("name"),
                jwt.getClaimAsString("preferred_username"),
                jwt.getClaimAsString("cognito:username"),
                email
        );
        return displayName.length() <= 100 ? displayName : displayName.substring(0, 100);
    }

    private String requiredClaim(Jwt jwt, String claimName, int maxLength) {
        String value = jwt.getClaimAsString(claimName);
        if (value == null || value.isBlank()) {
            throw new AuthenticationCredentialsNotFoundException(
                    "authenticated Cognito JWT is missing required claim: " + claimName
            );
        }
        String normalized = value.strip();
        if (normalized.length() > maxLength) {
            throw new IllegalArgumentException(claimName + " exceeds maximum length " + maxLength);
        }
        return normalized;
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.strip();
            }
        }
        throw new IllegalStateException("display name could not be resolved");
    }
}
