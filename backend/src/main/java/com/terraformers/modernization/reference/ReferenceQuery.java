package com.terraformers.modernization.reference;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Corpus-independent retrieval request derived solely from architecture facts. */
public record ReferenceQuery(String text, List<String> resourceTypes, int limit) {

    private static final Pattern RESOURCE_TYPE = Pattern.compile("\\baws_[a-z0-9_]+\\b");

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
        this(text, extractResourceTypes(text), limit);
    }

    private static List<String> extractResourceTypes(String text) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        Matcher matcher = RESOURCE_TYPE.matcher(text);
        java.util.ArrayList<String> resources = new java.util.ArrayList<>();
        while (matcher.find() && resources.size() < 8) {
            String value = matcher.group();
            if (!resources.contains(value)) {
                resources.add(value);
            }
        }
        return List.copyOf(resources);
    }
}
