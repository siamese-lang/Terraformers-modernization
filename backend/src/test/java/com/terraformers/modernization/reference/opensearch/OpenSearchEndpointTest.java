package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class OpenSearchEndpointTest {

    @Test
    void buildsSearchUriWithSchemeAndIndexPath() {
        assertThat(OpenSearchEndpoint.searchUri("example.us-east-1.aoss.amazonaws.com", "terraformers-reference").toString())
                .isEqualTo("https://example.us-east-1.aoss.amazonaws.com/terraformers-reference/_search");
    }

    @Test
    void preservesExplicitHttpsEndpoint() {
        assertThat(OpenSearchEndpoint.searchUri("https://example.com/", "idx").toString())
                .isEqualTo("https://example.com/idx/_search");
    }
}
