package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.http.SdkHttpFullRequest;

class SignedOpenSearchHttpClientTest {

    @Test
    void includesExactPayloadHashInRequestBeforeSigning() {
        String body = "{\"size\":0,\"query\":{\"match_all\":{}}}";

        SdkHttpFullRequest request = SignedOpenSearchHttpClient.buildUnsignedRequest(
                URI.create("https://example.ap-northeast-2.aoss.amazonaws.com/terraformers-reference-v1/_search"),
                body.getBytes(StandardCharsets.UTF_8));

        String payloadHash = request.headers().entrySet().stream()
                .filter(header -> "x-amz-content-sha256".equalsIgnoreCase(header.getKey()))
                .flatMap(header -> header.getValue().stream())
                .findFirst()
                .orElseThrow();

        assertThat(payloadHash).isEqualTo("ea835f2830c28623ce71c1ae128e004d5366c324924fe3db14e0e2a92094836e");
    }
}
