package com.terraformers.modernization.storage;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ObjectReference(
        @NotBlank @Size(max = 255) String bucket,
        @NotBlank @Size(max = 1024) String key
) {
}
