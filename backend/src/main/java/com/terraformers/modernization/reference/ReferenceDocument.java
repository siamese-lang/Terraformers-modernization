package com.terraformers.modernization.reference;

public record ReferenceDocument(
        String id,
        String title,
        String content,
        double score
) {
}
