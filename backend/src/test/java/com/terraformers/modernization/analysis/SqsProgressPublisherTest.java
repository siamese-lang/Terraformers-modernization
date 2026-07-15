package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageResponse;
import software.amazon.awssdk.services.sqs.model.SqsException;

class SqsProgressPublisherTest {

    private static final String QUEUE_URL = "https://sqs.ap-northeast-2.amazonaws.com/123456789012/terraformers-progress";

    @Test
    void publishSendsProgressEventToConfiguredQueue() {
        SqsClient sqsClient = mock(SqsClient.class);
        when(sqsClient.sendMessage(any(SendMessageRequest.class)))
                .thenReturn(SendMessageResponse.builder().messageId("message-1").build());
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setProgressQueueUrl(QUEUE_URL);
        SqsProgressPublisher publisher = new SqsProgressPublisher(
                () -> sqsClient,
                new ObjectMapper().findAndRegisterModules(),
                properties
        );

        publisher.publish(event());

        ArgumentCaptor<SendMessageRequest> requestCaptor = ArgumentCaptor.forClass(SendMessageRequest.class);
        verify(sqsClient).sendMessage(requestCaptor.capture());
        SendMessageRequest request = requestCaptor.getValue();
        assertThat(request.queueUrl()).isEqualTo(QUEUE_URL);
        assertThat(request.messageBody()).contains("analysis-job-1");
        assertThat(request.messageBody()).contains("terraformers-project");
        assertThat(request.messageBody()).contains("SUCCEEDED");
    }

    @Test
    void missingQueueUrlDoesNotFailAnalysisFlow() {
        SqsClient sqsClient = mock(SqsClient.class);
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        SqsProgressPublisher publisher = new SqsProgressPublisher(
                () -> sqsClient,
                new ObjectMapper().findAndRegisterModules(),
                properties
        );

        publisher.publish(event());

        verify(sqsClient, never()).sendMessage(any(SendMessageRequest.class));
    }

    @Test
    void sqsFailureDoesNotFailAnalysisFlow() {
        SqsClient sqsClient = mock(SqsClient.class);
        when(sqsClient.sendMessage(any(SendMessageRequest.class)))
                .thenThrow(SqsException.builder().message("queue unavailable").build());
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setProgressQueueUrl(QUEUE_URL);
        SqsProgressPublisher publisher = new SqsProgressPublisher(
                () -> sqsClient,
                new ObjectMapper().findAndRegisterModules(),
                properties
        );

        publisher.publish(event());

        verify(sqsClient).sendMessage(any(SendMessageRequest.class));
    }

    private ProgressEvent event() {
        return new ProgressEvent(
                "analysis-job-1",
                "terraformers-project",
                "upload-compat-1",
                AnalysisJobStatus.SUCCEEDED,
                "analysis job completed",
                Instant.parse("2026-07-15T00:00:00Z")
        );
    }
}
