package com.terraformers.modernization.projectcomment;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ProjectCommentCreateRequest(
        @NotBlank
        @Size(max = 4000)
        String content,

        @Size(max = 255)
        String userEmail
) {
}
