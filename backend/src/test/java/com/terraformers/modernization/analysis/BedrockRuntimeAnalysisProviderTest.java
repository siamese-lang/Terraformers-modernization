package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockRuntimeAnalysisProviderTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void invokesBedrockRuntimeAndExtractsAnthropicTextResponse() throws Exception {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("""
                                {
                                  "content": [
                                    {"type": "text", "text": "resource \\\"aws_s3_bucket\\\" \\\"example\\\" {}"}
                                  ]
                                }
                                """))
                        .build());

        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("anthropic.claude-3-haiku-20240307-v1:0");
        properties.setBedrockMaxTokens(1024);

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties
        );

        AnalysisResult result = provider.analyze(context());

        ArgumentCaptor<InvokeModelRequest> requestCaptor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(bedrockRuntimeClient).invokeModel(requestCaptor.capture());

        InvokeModelRequest request = requestCaptor.getValue();
        assertThat(request.modelId()).isEqualTo("anthropic.claude-3-haiku-20240307-v1:0");
        assertThat(request.contentType()).isEqualTo("application/json");
        assertThat(request.accept()).isEqualTo("application/json");

        JsonNode body = objectMapper.readTree(request.body().asUtf8String());
        assertThat(body.path("anthropic_version").asText()).isEqualTo("bedrock-2023-05-31");
        assertThat(body.path("max_tokens").asInt()).isEqualTo(1024);
        assertThat(body.path("messages").get(0).path("role").asText()).isEqualTo("user");
        assertThat(body.toString()).contains("projectId: project-123");
        assertThat(body.toString()).contains("sourceBucket: terraformers-source");
        assertThat(body.toString()).contains("sourceKey: browser-uploads/project-123/source.png");

        assertThat(result.provider()).isEqualTo("bedrock-runtime");
        assertThat(result.terraformCode()).isEqualTo("resource \"aws_s3_bucket\" \"example\" {}");
        assertThat(result.references()).containsExactly("s3://terraformers-source/browser-uploads/project-123/source.png");
    }

    @Test
    void missingModelIdFailsBeforeCallingBedrock() {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties
        );

        assertThatThrownBy(() -> provider.analyze(context()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("bedrock-model-id");

        verify(bedrockRuntimeClient, never()).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    void supportsLegacyCompletionTextShape() {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("{\"completion\":\"terraform block\"}"))
                        .build());

        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("legacy-model");

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties
        );

        AnalysisResult result = provider.analyze(context());

        assertThat(result.terraformCode()).isEqualTo("terraform block");
    }

    private AnalysisRequestContext context() {
        return new AnalysisRequestContext(
                "job-123",
                "project-123",
                "terraformers-source",
                "browser-uploads/project-123/source.png",
                "correlation-123",
                AnalysisMode.INTEGRATED_JAVA
        );
    }
}
