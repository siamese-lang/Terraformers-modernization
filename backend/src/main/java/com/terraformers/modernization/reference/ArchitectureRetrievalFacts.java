package com.terraformers.modernization.reference;

import java.util.List;

public record ArchitectureRetrievalFacts(String summary, List<String> components, List<String> relationships,
                                         List<String> resourceTypes) {
    public ArchitectureRetrievalFacts {
        summary = summary == null ? "" : summary.strip();
        components = normalize(components);
        relationships = normalize(relationships);
        resourceTypes = normalize(resourceTypes);
    }

    public boolean isEmpty() {
        return summary.isBlank() && components.isEmpty() && relationships.isEmpty() && resourceTypes.isEmpty();
    }

    private static List<String> normalize(List<String> values) {
        if (values == null) return List.of();
        return values.stream().filter(value -> value != null && !value.isBlank()).map(String::strip).toList();
    }
}
