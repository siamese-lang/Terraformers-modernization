package com.terraformers.modernization.project;

import jakarta.validation.constraints.NotNull;

public record ProjectVisibilityUpdateRequest(
        @NotNull ProjectVisibility visibility
) {
}
