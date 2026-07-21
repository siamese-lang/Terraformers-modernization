package com.terraformers.modernization.reference;

import java.util.List;

/** Corpus-independent retrieval request derived solely from architecture facts. */
public record ReferenceQuery(String text, List<String> resourceTypes, int limit) {

    public ReferenceQuery {
        text = text == null ? "" : text.strip();
        resourceTypes = resourceTypes == null
                ? List.of()
                : resourceTypes.stream()
                        .filter(value -> value != null && !value.isBlank())
                        .map(String::strip)
                        .distinct()
                        .limit(8)
                        .toList();
        if (text.isBlank()) {
            throw new IllegalArgumentException("reference query text must not be blank");
        }
        if (limit <= 0) {
            throw new IllegalArgumentException("reference query limit must be positive");
        }
    }

    public ReferenceQuery(String text, int limit) {
        this(text, List.of(), limit);
    }
}
