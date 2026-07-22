package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenSearchKnnQueryBuilderTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final OpenSearchKnnQueryBuilder builder = new OpenSearchKnnQueryBuilder(objectMapper);

    @Test
    void buildsVersionAndResourceFilteredKnnQueryBody() throws Exception {
        String body = builder.build(
                "embedding",
                "content",
                List.of(0.1f, 0.2f, 0.3f),
                8,
                "terraformers-reference-v2",
                "5.100.0",
                List.of("aws_vpc", "aws_subnet")
        );

        JsonNode root = objectMapper.readTree(body);
        JsonNode parameters = root.path("query").path("knn").path("embedding");
        JsonNode filters = parameters.path("filter").path("bool").path("filter");

        assertThat(root.path("size").asInt()).isEqualTo(8);
        assertThat(parameters.path("k").asInt()).isEqualTo(8);
        assertThat(parameters.path("vector").size()).isEqualTo(3);
        assertThat(filters.toString()).contains("terraformers-reference-v2", "5.100.0", "aws_vpc", "aws_subnet");
        assertThat(root.path("_source").toString()).contains("documentId", "authority", "riskTags", "content");
    }

    @Test
    void keepsUnfilteredCompatibilityOverload() throws Exception {
        String body = builder.build("embedding", "content", List.of(0.1f), 1);

        JsonNode parameters = objectMapper.readTree(body).path("query").path("knn").path("embedding");
        assertThat(parameters.has("filter")).isFalse();
    }
}
