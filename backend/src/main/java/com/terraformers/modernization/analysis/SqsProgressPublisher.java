package com.terraformers.modernization.analysis;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "sqs-publisher-enabled", havingValue = "true")
public class SqsProgressPublisher implements ProgressPublisher {

    private final SqsClient sqsClient;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;

    public SqsProgressPublisher(ObjectMapper objectMapper, AnalysisRuntimeProperties properties) {
        this.sqsClient = SqsClient.builder().build();
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    @Override
    public void publish(ProgressEvent event) {
        if (properties.getProgressQueueUrl() == null || properties.getProgressQueueUrl().isBlank()) {
            throw new IllegalStateException("terraformers.analysis.progress-queue-url must be set when SQS publisher is enabled");
        }

        sqsClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(properties.getProgressQueueUrl())
                .messageBody(toJson(event))
                .build());
    }

    private String toJson(ProgressEvent event) {
        try {
            return objectMapper.writeValueAsString(event);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to serialize progress event", exception);
        }
    }
}
