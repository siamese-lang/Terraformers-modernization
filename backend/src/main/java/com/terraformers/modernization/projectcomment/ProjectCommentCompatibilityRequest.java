package com.terraformers.modernization.projectcomment;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ProjectCommentCompatibilityRequest(
        @NotBlank
        @Size(max = 64)
        String projectId,

        @NotBlank
        @Size(max = 4000)
        String content,

        @Size(max = 255)
        String userEmail
) {
    ProjectCommentCreateRequest toCreateRequest() {
        return new ProjectCommentCreateRequest(content, userEmail);
    }
}
