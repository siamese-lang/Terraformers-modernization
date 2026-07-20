package com.terraformers.modernization.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.RetrievalMode;
import java.util.List;
import org.junit.jupiter.api.Test;

class RuntimeAdapterContractValidatorTest {

    @Test
    void disabledAdaptersDoNotRequirePlaceholderSettings() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        RuntimeAdapterContractValidator validator = new RuntimeAdapterContractValidator(properties);

        assertThat(validator.findMissingEnabledAdapterSettings()).isEmpty();
        assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
    }

    @Test
    void enabledAdaptersReportOnlyTheirMissingSettings() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockProviderEnabled(true);
        properties.setRetrievalMode(RetrievalMode.REQUIRED);
        properties.setSqsPublisherEnabled(true);
        properties.setOpensearchEndpoint("https://search.example.com");
        properties.setIndexName("terraform-reference");

        RuntimeAdapterContractValidator validator = new RuntimeAdapterContractValidator(properties);

        assertThat(validator.findMissingEnabledAdapterSettings())
                .containsExactly(
                        "BEDROCK_MODEL_ID",
                        "BEDROCK_EMBEDDING_MODEL_ID",
                        "VECTOR_FIELD_NAME",
                        "CONTENT_FIELD_NAME",
                        "AI_LOG_QUEUE_URL",
                        "TERRAFORM_LOG_QUEUE_URL"
                );
        assertThatThrownBy(() -> validator.run(null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("BEDROCK_MODEL_ID")
                .hasMessageContaining("AI_LOG_QUEUE_URL");
    }

    @Test
    void enabledAdaptersPassWhenTheirOwnSettingsArePresent() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockProviderEnabled(true);
        properties.setBedrockModelId("bedrock-model");
        properties.setBedrockEmbeddingModelId("embedding-model");
        properties.setRetrievalMode(RetrievalMode.REQUIRED);
        properties.setOpensearchEndpoint("https://search.example.com");
        properties.setIndexName("terraform-reference");
        properties.setVectorFieldName("vector");
        properties.setContentFieldName("content");
        properties.setSqsPublisherEnabled(true);
        properties.setProgressQueueUrl("https://sqs.example.com/progress");
        properties.setResultQueueUrl("https://sqs.example.com/result");

        RuntimeAdapterContractValidator validator = new RuntimeAdapterContractValidator(properties);

        assertThat(validator.findMissingEnabledAdapterSettings()).isEqualTo(List.of());
        assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
    }
}
