package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import java.io.IOException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenSearchReferenceRetrieverTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void sendsReferenceQueryToConfiguredOpenSearchIndexAndParsesHits() throws Exception {
        AnalysisRuntimeProperties properties = properties();
        CapturingHttpClient httpClient = new CapturingHttpClient("""
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
                """, 200);

        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(httpClient, objectMapper, properties);

        List<ReferenceDocument> documents = retriever.retrieve(new ReferenceQuery(
                "project-1",
                "source-bucket",
                "uploads/architecture.png",
                "image/png",
                List.of("vpc", "rds", "s3"),
                2
        ));

        assertThat(httpClient.capturedRequest.uri().toString())
                .isEqualTo("https://search.example.com/terraform-reference/_search");
        assertThat(httpClient.capturedRequest.headers().firstValue("Content-Type"))
                .contains("application/json");
        assertThat(httpClient.capturedBody)
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

    @Test
    void missingEndpointFailsBeforeHttpCall() {
        AnalysisRuntimeProperties properties = properties();
        properties.setOpensearchEndpoint(null);
        CapturingHttpClient httpClient = new CapturingHttpClient("{}", 200);
        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(httpClient, objectMapper, properties);

        assertThatThrownBy(() -> retriever.retrieve(ReferenceQuery.fromObject(
                "project-1",
                "bucket",
                "source.png",
                "image/png"
        )))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("terraformers.analysis.opensearch-endpoint");
        assertThat(httpClient.sendCount).isZero();
    }

    @Test
    void nonSuccessStatusFailsRetrieval() {
        CapturingHttpClient httpClient = new CapturingHttpClient("{\"error\":\"boom\"}", 500);
        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(httpClient, objectMapper, properties());

        assertThatThrownBy(() -> retriever.retrieve(ReferenceQuery.fromObject(
                "project-1",
                "bucket",
                "source.png",
                "image/png"
        )))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("status 500");
    }

    private AnalysisRuntimeProperties properties() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setOpensearchEndpoint("https://search.example.com/");
        properties.setIndexName("terraform-reference");
        properties.setContentFieldName("content");
        properties.setOpensearchTopK(3);
        return properties;
    }

    private static class CapturingHttpClient extends HttpClient {
        private final String responseBody;
        private final int statusCode;
        private HttpRequest capturedRequest;
        private String capturedBody;
        private int sendCount;

        private CapturingHttpClient(String responseBody, int statusCode) {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
        }

        @Override
        public <T> HttpResponse<T> send(HttpRequest request, HttpResponse.BodyHandler<T> responseBodyHandler)
                throws IOException, InterruptedException {
            sendCount++;
            capturedRequest = request;
            capturedBody = readBody(request);
            @SuppressWarnings("unchecked")
            T body = (T) responseBody;
            return new TestHttpResponse<>(request, statusCode, body);
        }

        @Override
        public <T> java.util.concurrent.CompletableFuture<HttpResponse<T>> sendAsync(
                HttpRequest request,
                HttpResponse.BodyHandler<T> responseBodyHandler
        ) {
            throw new UnsupportedOperationException("sendAsync is not used by this contract test");
        }

        @Override
        public <T> java.util.concurrent.CompletableFuture<HttpResponse<T>> sendAsync(
                HttpRequest request,
                HttpResponse.BodyHandler<T> responseBodyHandler,
                HttpResponse.PushPromiseHandler<T> pushPromiseHandler
        ) {
            throw new UnsupportedOperationException("sendAsync is not used by this contract test");
        }

        @Override
        public java.util.Optional<java.net.CookieHandler> cookieHandler() {
            return java.util.Optional.empty();
        }

        @Override
        public java.util.Optional<java.time.Duration> connectTimeout() {
            return java.util.Optional.empty();
        }

        @Override
        public Redirect followRedirects() {
            return Redirect.NEVER;
        }

        @Override
        public java.util.Optional<java.net.ProxySelector> proxy() {
            return java.util.Optional.empty();
        }

        @Override
        public javax.net.ssl.SSLContext sslContext() {
            return null;
        }

        @Override
        public javax.net.ssl.SSLParameters sslParameters() {
            return null;
        }

        @Override
        public java.util.Optional<java.net.Authenticator> authenticator() {
            return java.util.Optional.empty();
        }

        @Override
        public Version version() {
            return Version.HTTP_1_1;
        }

        @Override
        public java.util.concurrent.Executor executor() {
            return null;
        }

        private String readBody(HttpRequest request) throws IOException {
            CapturingSubscriber subscriber = new CapturingSubscriber();
            request.bodyPublisher().orElseThrow().subscribe(subscriber);
            return subscriber.body();
        }
    }

    private record TestHttpResponse<T>(HttpRequest request, int statusCode, T body) implements HttpResponse<T> {
        @Override
        public java.util.Optional<HttpResponse<T>> previousResponse() {
            return java.util.Optional.empty();
        }

        @Override
        public HttpHeaders headers() {
            return HttpHeaders.of(java.util.Map.of(), (left, right) -> true);
        }

        @Override
        public java.util.Optional<javax.net.ssl.SSLSession> sslSession() {
            return java.util.Optional.empty();
        }

        @Override
        public URI uri() {
            return request.uri();
        }

        @Override
        public Version version() {
            return Version.HTTP_1_1;
        }
    }

    private static class CapturingSubscriber implements java.util.concurrent.Flow.Subscriber<java.nio.ByteBuffer> {
        private final java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();

        @Override
        public void onSubscribe(java.util.concurrent.Flow.Subscription subscription) {
            subscription.request(Long.MAX_VALUE);
        }

        @Override
        public void onNext(java.nio.ByteBuffer item) {
            byte[] bytes = new byte[item.remaining()];
            item.get(bytes);
            output.writeBytes(bytes);
        }

        @Override
        public void onError(Throwable throwable) {
            throw new IllegalStateException("failed to capture request body", throwable);
        }

        @Override
        public void onComplete() {
        }

        private String body() {
            return output.toString(java.nio.charset.StandardCharsets.UTF_8);
        }
    }
}
