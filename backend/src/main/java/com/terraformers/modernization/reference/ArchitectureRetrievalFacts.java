package com.terraformers.modernization.reference;

import java.util.List;

public record ArchitectureRetrievalFacts(String summary, List<String> components, List<String> relationships,
                                         List<String> resourceTypes) {
    public boolean isEmpty() {
        return (summary == null || summary.isBlank())
                && components.stream().allMatch(String::isBlank)
                && relationships.stream().allMatch(String::isBlank)
                && resourceTypes.stream().allMatch(String::isBlank);
    }
}
