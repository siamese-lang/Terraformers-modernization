package com.terraformers.modernization.reference.opensearch;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
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

        Map<String, Object> body = Map.of(
                "size", topK,
                "_source", List.of("id", "title", contentFieldName),
                "query", Map.of(
                        "knn", Map.of(
                                vectorFieldName, Map.of(
                                        "vector", vector,
                                        "k", topK
                                )
                        )
                )
        );

        try {
            return objectMapper.writeValueAsString(body);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to build OpenSearch k-NN query", exception);
        }
    }
}
