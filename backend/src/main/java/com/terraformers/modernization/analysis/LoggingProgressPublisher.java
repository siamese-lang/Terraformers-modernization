package com.terraformers.modernization.analysis;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "sqs-publisher-enabled", havingValue = "false", matchIfMissing = true)
public class LoggingProgressPublisher implements ProgressPublisher {

    private static final Logger log = LoggerFactory.getLogger(LoggingProgressPublisher.class);

    @Override
    public void publish(ProgressEvent event) {
        log.info("analysis progress jobId={} projectId={} status={} message={}",
                event.jobId(), event.projectId(), event.status(), event.message());
    }
}
