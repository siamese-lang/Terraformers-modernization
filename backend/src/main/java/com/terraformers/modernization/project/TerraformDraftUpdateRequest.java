package com.terraformers.modernization.project;

import jakarta.validation.constraints.NotNull;

public record TerraformDraftUpdateRequest(
        @NotNull String content
) {
}
