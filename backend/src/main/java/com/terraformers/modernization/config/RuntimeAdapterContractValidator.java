package com.terraformers.modernization.config;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.analysis.AnalysisMode;
import com.terraformers.modernization.reference.RetrievalMode;
import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("prod")
public class RuntimeAdapterContractValidator implements ApplicationRunner {

    private final AnalysisRuntimeProperties properties;

    public RuntimeAdapterContractValidator(AnalysisRuntimeProperties properties) {
        this.properties = properties;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<String> missing = findMissingEnabledAdapterSettings();
        if (!missing.isEmpty()) {
            throw new IllegalStateException(
                    "Enabled runtime adapters are missing required configuration: " + String.join(", ", missing)
            );
        }
    }

    List<String> findMissingEnabledAdapterSettings() {
        List<String> missing = new ArrayList<>();

        if (properties.getMode() == AnalysisMode.EXTERNAL_PYTHON_LEGACY) {
            missing.add("ANALYSIS_MODE_INTEGRATED_JAVA");
        }

        if (properties.isBedrockProviderEnabled()) {
            requireText(missing, "BEDROCK_MODEL_ID", properties.getBedrockModelId());
        }
        if (properties.getRetrievalMode() != null && properties.getRetrievalMode() != RetrievalMode.DISABLED) {
            if (!properties.isBedrockProviderEnabled()) missing.add("BEDROCK_PROVIDER_ENABLED");
            requireText(missing, "BEDROCK_EMBEDDING_MODEL_ID", properties.getBedrockEmbeddingModelId());
            requireText(missing, "OPENSEARCH_ENDPOINT", properties.getOpensearchEndpoint());
            requireText(missing, "INDEX_NAME", properties.getIndexName());
            requireText(missing, "VECTOR_FIELD_NAME", properties.getVectorFieldName());
            requireText(missing, "CONTENT_FIELD_NAME", properties.getContentFieldName());
        }
        if (properties.isSqsPublisherEnabled()) {
            requireText(missing, "AI_LOG_QUEUE_URL", properties.getProgressQueueUrl());
            requireText(missing, "TERRAFORM_LOG_QUEUE_URL", properties.getResultQueueUrl());
        }

        return List.copyOf(missing);
    }

    private void requireText(List<String> missing, String environmentName, String value) {
        if (value == null || value.isBlank()) {
            missing.add(environmentName);
        }
    }
}
