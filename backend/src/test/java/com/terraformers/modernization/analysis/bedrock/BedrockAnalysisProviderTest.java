package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisMode;
import com.terraformers.modernization.analysis.AnalysisRequestContext;
import com.terraformers.modernization.analysis.AnalysisResult;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.reference.BedrockArchitectureFactsExtractor;
import com.terraformers.modernization.reference.RetrievalQueryTextBuilder;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectMetadata;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockAnalysisProviderTest {
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void invokesConfiguredModelWithImageBytesAndTaggedStructuredResponse() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(InvokeModelResponse.builder()
                .body(SdkBytes.fromUtf8String(claudeResponse("""
                        <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"Private web stack","components":["VPC","ALB"],"relationships":["ALB forwards to service"],"warnings":[]}</analysis_json>
                        <terraform_hcl>resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }</terraform_hcl>
                        """)))
                .build());
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("configured-model-id");
        properties.setBedrockMaxTokens(2048);
        properties.setRetrievalMode(com.terraformers.modernization.reference.RetrievalMode.DISABLED);

        BedrockAnalysisProvider provider = new BedrockAnalysisProvider(
                client,
                objectReader(),
                referenceRetriever(),
                properties,
                new BedrockPromptBuilder(objectMapper),
                new BedrockResponseParser(objectMapper),
                new BedrockArchitectureFactsExtractor(client, objectMapper, properties),
                new RetrievalQueryTextBuilder()
        );

        AnalysisResult result = provider.analyze(context());

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(captor.capture());
        InvokeModelRequest request = captor.getValue();
        assertThat(request.modelId()).isEqualTo("configured-model-id");
        JsonNode body = objectMapper.readTree(request.body().asUtf8String());
        assertThat(body.path("messages").get(0).path("content").get(0).path("type").asText()).isEqualTo("image");
        assertThat(body.toString()).contains("<analysis_json>");
        assertThat(body.toString()).contains("<terraform_hcl>");
        assertThat(body.toString()).doesNotContain("terraformCode");
        assertThat(body.toString()).doesNotContain("Use private subnets");
        assertThat(result.provider()).isEqualTo("bedrock:configured-model-id");
        assertThat(result.explanation()).isEqualTo("Private web stack");
        assertThat(result.components()).containsExactly("VPC", "ALB");
        assertThat(result.relationships()).containsExactly("ALB forwards to service");
        assertThat(result.terraformCode()).contains("resource \"aws_vpc\"");
        assertThat(result.references()).isEmpty();
    }

    @Test
    void retriesOnceWithCompactPromptWhenStandardOutputIsTruncated() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(response("partial", "max_tokens", 8192))
                .thenReturn(response(validResponseText(), "end_turn", 300));

        AnalysisResult result = provider(client).analyze(context());

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client, times(2)).invokeModel(captor.capture());
        List<InvokeModelRequest> requests = captor.getAllValues();
        assertThat(requests.get(0).body().asUtf8String()).contains("Standard-output requirements");
        assertThat(requests.get(1).body().asUtf8String()).contains("Compact-output requirements");
        assertThat(result.explanation()).isEqualTo("Private web stack");
    }

    @Test
    void propagatesTruncationAfterCompactRetryAlsoTruncates() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(response("partial", "max_tokens", 8192))
                .thenReturn(response("still partial", "max_tokens", 8192));

        assertThatThrownBy(() -> provider(client).analyze(context()))
                .isInstanceOf(BedrockOutputTruncatedException.class);
        verify(client, times(2)).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    void doesNotRetryFormatOrRuntimeErrors() throws Exception {
        BedrockRuntimeClient formatClient = mock(BedrockRuntimeClient.class);
        when(formatClient.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("not tagged", "end_turn", 10));
        assertThatThrownBy(() -> provider(formatClient).analyze(context())).isInstanceOf(BedrockResponseFormatException.class);
        verify(formatClient, times(1)).invokeModel(any(InvokeModelRequest.class));

        BedrockRuntimeClient runtimeClient = mock(BedrockRuntimeClient.class);
        when(runtimeClient.invokeModel(any(InvokeModelRequest.class))).thenThrow(new IllegalStateException("network unavailable"));
        assertThatThrownBy(() -> provider(runtimeClient).analyze(context())).isInstanceOf(IllegalStateException.class);
        verify(runtimeClient, times(1)).invokeModel(any(InvokeModelRequest.class));

        BedrockRuntimeClient timeoutClient = mock(BedrockRuntimeClient.class);
        when(timeoutClient.invokeModel(any(InvokeModelRequest.class)))
                .thenThrow(SdkClientException.builder().message("Read timed out").build());
        assertThatThrownBy(() -> provider(timeoutClient).analyze(context())).isInstanceOf(SdkClientException.class);
        verify(timeoutClient, times(1)).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    void doesNotRetryRejectedInput() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("""
                <analysis_json>{"inputType":"NON_ARCHITECTURE_IMAGE","classificationConfidence":0.98,"classificationReason":"This is a photo.","summary":"","components":[],"relationships":[],"warnings":[]}</analysis_json>
                <terraform_hcl></terraform_hcl>
                """, "end_turn", 10));
        assertThatThrownBy(() -> provider(client).analyze(context())).isInstanceOf(ArchitectureInputRejectedException.class);
        verify(client, times(1)).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    void propagatesRejectedInputAfterTheSingleCompactRetry() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(response("partial", "max_tokens", 8192))
                .thenReturn(response("""
                        <analysis_json>{"inputType":"AMBIGUOUS","classificationConfidence":0.4,"classificationReason":"Relationships are not clear.","summary":"","components":[],"relationships":[],"warnings":[]}</analysis_json>
                        <terraform_hcl></terraform_hcl>
                        """, "end_turn", 10));
        assertThatThrownBy(() -> provider(client).analyze(context())).isInstanceOf(ArchitectureInputRejectedException.class);
        verify(client, times(2)).invokeModel(any(InvokeModelRequest.class));
    }

    private BedrockAnalysisProvider provider(BedrockRuntimeClient client) {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("configured-model-id");
        properties.setBedrockMaxTokens(8192);
        return new BedrockAnalysisProvider(client, objectReader(), referenceRetriever(), properties,
                new BedrockPromptBuilder(objectMapper), new BedrockResponseParser(objectMapper),
                new BedrockArchitectureFactsExtractor(client, objectMapper, properties), new RetrievalQueryTextBuilder());
    }

    private InvokeModelResponse response(String text, String stopReason, int outputTokens) throws Exception {
        return InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(claudeResponse(text, stopReason, outputTokens))).build();
    }

    private String validResponseText() {
        return """
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"Private web stack","components":["VPC","ALB"],"relationships":["ALB forwards to service"],"warnings":[]}</analysis_json>
                <terraform_hcl>resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }</terraform_hcl>
                """;
    }

    private String claudeResponse(String text) throws Exception {
        return objectMapper.writeValueAsString(Map.of(
                "content", List.of(Map.of(
                        "type", "text",
                        "text", text
                ))
        ));
    }

    private String claudeResponse(String text, String stopReason, int outputTokens) throws Exception {
        return objectMapper.writeValueAsString(Map.of(
                "content", List.of(Map.of("type", "text", "text", text)),
                "stop_reason", stopReason,
                "usage", Map.of("output_tokens", outputTokens)
        ));
    }

    private ObjectReader objectReader() {
        return new ObjectReader() {
            @Override
            public ObjectMetadata readMetadata(ObjectReference reference) {
                return metadata(reference);
            }

            @Override
            public ObjectContent readContent(ObjectReference reference) {
                return new ObjectContent(metadata(reference), "image bytes".getBytes(StandardCharsets.UTF_8));
            }

            private ObjectMetadata metadata(ObjectReference reference) {
                return new ObjectMetadata(reference.bucket(), reference.key(), "image/png", 11L, "etag");
            }
        };
    }

    private ReferenceRetriever referenceRetriever() {
        return query -> List.of(new ReferenceDocument("ref-1", "Reference", "Use private subnets", 1.0));
    }

    private AnalysisRequestContext context() {
        return new AnalysisRequestContext("job", "project", "bucket", "key.png", "corr", AnalysisMode.INTEGRATED_JAVA);
    }
}
