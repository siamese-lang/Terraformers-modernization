package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenSearchReferenceRetrieverTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void sendsReferenceQueryToConfiguredOpenSearchIndexAndParsesHits() throws Exception {
        try (MockOpenSearchServer server = MockOpenSearchServer.start("""
                {
                  "hits": {
                    "hits": [
                      {
                        "_id": "doc-1",
                        "_score": 7.5,
                        "_source": {
                          "title": "VPC RDS S3 reference",
                          "content": "Use VPC networking with RDS and object storage separation."
                        }
                      }
                    ]
                  }
                }
                """, 200)) {
            AnalysisRuntimeProperties properties = properties(server.endpoint());
            OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(
                    HttpClient.newHttpClient(),
                    objectMapper,
                    properties
            );

            List<ReferenceDocument> documents = retriever.retrieve(new ReferenceQuery(
                    "project-1",
                    "source-bucket",
                    "uploads/architecture.png",
                    "image/png",
                    List.of("vpc", "rds", "s3"),
                    2
            ));

            assertThat(server.requestPath).isEqualTo("/terraform-reference/_search");
            assertThat(server.requestMethod).isEqualTo("POST");
            assertThat(server.requestContentType).contains("application/json");
            assertThat(server.requestBody)
                    .contains("project-1")
                    .contains("image/png")
                    .contains("uploads/architecture.png")
                    .contains("vpc")
                    .contains("title^2")
                    .contains("content")
                    .contains("\"size\":2");

            assertThat(documents).hasSize(1);
            assertThat(documents.get(0).id()).isEqualTo("doc-1");
            assertThat(documents.get(0).title()).isEqualTo("VPC RDS S3 reference");
            assertThat(documents.get(0).content()).contains("object storage separation");
            assertThat(documents.get(0).score()).isEqualTo(7.5);
        }
    }

    @Test
    void missingEndpointFailsBeforeHttpCall() {
        AnalysisRuntimeProperties properties = properties("https://search.example.com/");
        properties.setOpensearchEndpoint(null);
        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(
                HttpClient.newHttpClient(),
                objectMapper,
                properties
        );

        assertThatThrownBy(() -> retriever.retrieve(ReferenceQuery.fromObject(
                "project-1",
                "bucket",
                "source.png",
                "image/png"
        )))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("terraformers.analysis.opensearch-endpoint");
    }

    @Test
    void nonSuccessStatusFailsRetrieval() throws Exception {
        try (MockOpenSearchServer server = MockOpenSearchServer.start("{\"error\":\"boom\"}", 500)) {
            OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(
                    HttpClient.newHttpClient(),
                    objectMapper,
                    properties(server.endpoint())
            );

            assertThatThrownBy(() -> retriever.retrieve(ReferenceQuery.fromObject(
                    "project-1",
                    "bucket",
                    "source.png",
                    "image/png"
            )))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("status 500");
        }
    }

    private AnalysisRuntimeProperties properties(String endpoint) {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setOpensearchEndpoint(endpoint);
        properties.setIndexName("terraform-reference");
        properties.setContentFieldName("content");
        properties.setOpensearchTopK(3);
        return properties;
    }

    private static class MockOpenSearchServer implements AutoCloseable {
        private final HttpServer server;
        private final String responseBody;
        private final int statusCode;
        private String requestMethod;
        private String requestPath;
        private String requestContentType;
        private String requestBody;

        private MockOpenSearchServer(String responseBody, int statusCode) throws IOException {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
            this.server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            this.server.createContext("/", exchange -> {
                requestMethod = exchange.getRequestMethod();
                requestPath = exchange.getRequestURI().getPath();
                requestContentType = exchange.getRequestHeaders().getFirst("Content-Type");
                requestBody = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);

                byte[] responseBytes = this.responseBody.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(this.statusCode, responseBytes.length);
                try (OutputStream output = exchange.getResponseBody()) {
                    output.write(responseBytes);
                }
            });
            this.server.start();
        }

        private static MockOpenSearchServer start(String responseBody, int statusCode) throws IOException {
            return new MockOpenSearchServer(responseBody, statusCode);
        }

        private String endpoint() {
            return "http://127.0.0.1:" + server.getAddress().getPort();
        }

        @Override
        public void close() {
            server.stop(0);
        }
    }
}
