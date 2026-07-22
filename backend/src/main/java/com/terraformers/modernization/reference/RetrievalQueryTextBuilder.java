package com.terraformers.modernization.reference;

import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

@Component
public class RetrievalQueryTextBuilder {
    public String build(ArchitectureRetrievalFacts facts) {
        if (facts == null || facts.isEmpty()) {
            throw new IllegalStateException("architecture retrieval facts must not be empty");
        }
        return "Architecture summary: %s. Components: %s. Relationships: %s. Terraform resource candidates: %s."
                .formatted(facts.summary(), join(facts.components()), join(facts.relationships()), join(facts.resourceTypes()));
    }

    private String join(java.util.List<String> values) {
        return values.stream().filter(value -> value != null && !value.isBlank()).collect(Collectors.joining(", "));
    }
}
