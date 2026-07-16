package com.terraformers.modernization.projectcomment;

import com.terraformers.modernization.collaboration.CommentEntity;
import com.terraformers.modernization.identity.UserEntity;
import java.time.Instant;

public record ProjectCommentResponse(
        Long id,
        Long projectId,
        String content,
        String userEmail,
        Instant createdAt
) {
    static ProjectCommentResponse from(CommentEntity entity) {
        return new ProjectCommentResponse(
                entity.getCommentId(),
                entity.getBoard().getProject().getProjectId(),
                entity.getContent(),
                displayAuthor(entity.getAuthor()),
                entity.getCreatedAt()
        );
    }

    private static String displayAuthor(UserEntity author) {
        if (author.getEmail() != null && !author.getEmail().isBlank()) {
            return author.getEmail();
        }
        if (author.getDisplayName() != null && !author.getDisplayName().isBlank()) {
            return author.getDisplayName();
        }
        return author.getCognitoSub();
    }
}
