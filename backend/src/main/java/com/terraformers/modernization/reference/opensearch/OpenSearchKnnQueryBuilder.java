package com.terraformers.modernization.reference.opensearch;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

@Component
public class OpenSearchKnnQueryBuilder {

    private final ObjectMapper objectMapper;

    public OpenSearchKnnQueryBuilder(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String build(String vectorFieldName, String contentFieldName, List<Float> vector, int topK) {
        return build(vectorFieldName, contentFieldName, vector, topK, "", "", List.of());
    }

    public String build(
            String vectorFieldName,
            String contentFieldName,
            List<Float> vector,
            int topK,
            String corpusVersion,
            String providerVersion,
            List<String> resourceTypes
    ) {
        if (vectorFieldName == null || vectorFieldName.isBlank()) {
            throw new IllegalArgumentException("vector field name must be set");
        }
        if (contentFieldName == null || contentFieldName.isBlank()) {
            throw new IllegalArgumentException("content field name must be set");
        }
        if (vector == null || vector.isEmpty()) {
            throw new IllegalArgumentException("embedding vector must not be empty");
        }
        if (topK <= 0) {
            throw new IllegalArgumentException("topK must be positive");
        }

        List<Map<String, Object>> filters = new ArrayList<>();
        addTermFilter(filters, "corpusVersion", corpusVersion);
        addTermFilter(filters, "providerVersion", providerVersion);
        List<String> normalizedResourceTypes = resourceTypes == null
                ? List.of()
                : resourceTypes.stream()
                        .filter(value -> value != null && !value.isBlank())
                        .map(String::strip)
                        .distinct()
                        .toList();
        if (!normalizedResourceTypes.isEmpty()) {
            filters.add(Map.of("terms", Map.of("resourceTypes", normalizedResourceTypes)));
        }

        Map<String, Object> knnParameters = new LinkedHashMap<>();
        knnParameters.put("vector", vector);
        knnParameters.put("k", topK);
        if (!filters.isEmpty()) {
            knnParameters.put(
                    "filter",
                    filters.size() == 1
                            ? filters.get(0)
                            : Map.of("bool", Map.of("filter", filters))
            );
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("size", topK);
        body.put("_source", List.of(
                "documentId",
                "id",
                "title",
                contentFieldName,
                "documentType",
                "resourceTypes",
                "sourcePath",
                "providerVersion",
                "corpusVersion",
                "authority",
                "priority",
                "riskTags"
        ));
        body.put("query", Map.of(
                "knn", Map.of(
                        vectorFieldName, knnParameters
                )
        ));

        try {
            return objectMapper.writeValueAsString(body);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to build OpenSearch k-NN query", exception);
        }
    }

    private void addTermFilter(List<Map<String, Object>> filters, String field, String value) {
        if (value != null && !value.isBlank()) {
            filters.add(Map.of("term", Map.of(field, value.strip())));
        }
    }
}
