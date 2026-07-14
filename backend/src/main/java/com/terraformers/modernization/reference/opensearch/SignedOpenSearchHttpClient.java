package com.terraformers.modernization.reference.opensearch;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.signer.Aws4Signer;
import software.amazon.awssdk.auth.signer.params.Aws4SignerParams;
import software.amazon.awssdk.http.SdkHttpFullRequest;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.regions.Region;

@Component
public class SignedOpenSearchHttpClient {

    private final HttpClient httpClient;
    private final Aws4Signer signer;
    private final AwsCredentialsProvider credentialsProvider;
    private final Region region;

    public SignedOpenSearchHttpClient() {
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
        this.signer = Aws4Signer.create();
        this.credentialsProvider = DefaultCredentialsProvider.create();
        this.region = resolveRegion();
    }

    public String post(URI uri, String body, String serviceName) {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        SdkHttpFullRequest unsignedRequest = SdkHttpFullRequest.builder()
                .method(SdkHttpMethod.POST)
                .uri(uri)
                .putHeader("Host", uri.getHost())
                .putHeader("Content-Type", "application/json")
                .contentStreamProvider(() -> new ByteArrayInputStream(bytes))
                .build();

        SdkHttpFullRequest signedRequest = signer.sign(unsignedRequest, Aws4SignerParams.builder()
                .awsCredentials(credentialsProvider.resolveCredentials())
                .signingName(serviceName)
                .signingRegion(region)
                .build());

        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(30))
                .POST(HttpRequest.BodyPublishers.ofByteArray(bytes));

        for (Map.Entry<String, List<String>> header : signedRequest.headers().entrySet()) {
            if ("host".equalsIgnoreCase(header.getKey())) {
                continue;
            }
            for (String value : header.getValue()) {
                builder.header(header.getKey(), value);
            }
        }

        try {
            HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new IllegalStateException("OpenSearch query failed with HTTP " + response.statusCode());
            }
            return response.body();
        } catch (IOException exception) {
            throw new IllegalStateException("OpenSearch query I/O failure", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("OpenSearch query interrupted", exception);
        }
    }

    private Region resolveRegion() {
        String regionName = System.getenv("AWS_REGION");
        if (regionName == null || regionName.isBlank()) {
            regionName = System.getenv("AWS_DEFAULT_REGION");
        }
        if (regionName == null || regionName.isBlank()) {
            regionName = "ap-northeast-2";
        }
        return Region.of(regionName);
    }
}
