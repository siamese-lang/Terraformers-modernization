package com.terraformers.modernization.analysis;

public record TerraformDraftValidation(boolean valid, String sanitizedContent, String reason) {
}
