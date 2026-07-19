package com.terraformers.modernization.projectcomment;

import com.terraformers.modernization.collaboration.CommentEntity;
import com.terraformers.modernization.identity.UserEntity;
import java.time.Instant;

public record ProjectCommentResponse(
        Long id,
        Long projectId,
        String content,
        String authorDisplayName,
        String userEmail,
        Instant createdAt
) {
    private static final String UUID_PATTERN =
            "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$";
    static ProjectCommentResponse from(CommentEntity entity) {
        return new ProjectCommentResponse(
                entity.getCommentId(),
                entity.getBoard().getProject().getProjectId(),
                entity.getContent(),
                displayAuthor(entity.getAuthor()),
                safeEmail(entity.getAuthor()),
                entity.getCreatedAt()
        );
    }

    private static String displayAuthor(UserEntity author) {
        if (isSafeDisplayName(author)) {
            return author.getDisplayName().strip();
        }
        return safeEmail(author) != null ? safeEmail(author) : "사용자";
    }

    private static boolean isSafeDisplayName(UserEntity author) {
        String displayName = author.getDisplayName();
        return displayName != null && !displayName.isBlank()
                && !displayName.strip().equals(author.getCognitoSub())
                && !displayName.strip().matches(UUID_PATTERN);
    }

    private static String safeEmail(UserEntity author) {
        if (author.getEmail() == null || author.getEmail().isBlank()) {
            return null;
        }
        String email = author.getEmail().strip();
        int at = email.indexOf('@');
        return at > 0 ? email.substring(0, 1) + "***" + email.substring(at) : "사용자";
    }
}
