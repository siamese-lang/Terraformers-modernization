package com.terraformers.modernization.identity;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DisplayNameUpdateRequest(
        @NotBlank @Size(max = 100) String displayName
) {
}
