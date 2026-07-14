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
    void buildsKnnQueryBody() throws Exception {
        String body = builder.build("embedding", "content", List.of(0.1f, 0.2f, 0.3f), 3);

        JsonNode root = objectMapper.readTree(body);
        assertThat(root.path("size").asInt()).isEqualTo(3);
        assertThat(root.path("query").path("knn").path("embedding").path("k").asInt()).isEqualTo(3);
        assertThat(root.path("query").path("knn").path("embedding").path("vector")).hasSize(3);
        assertThat(root.path("_source").toString()).contains("content");
    }
}
