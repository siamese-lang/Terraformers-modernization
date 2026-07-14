package com.terraformers.modernization.storage;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.storage", name = "s3-writer-enabled", havingValue = "false", matchIfMissing = true)
public class StubObjectWriter implements ObjectWriter {

    @Override
    public ObjectWriteResult writeText(ObjectWriteRequest request) {
        return new ObjectWriteResult(
                request.bucket(),
                request.key(),
                "stub-etag"
        );
    }
}
