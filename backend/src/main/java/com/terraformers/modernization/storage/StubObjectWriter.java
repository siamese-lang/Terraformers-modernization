package com.terraformers.modernization.storage;

import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnMissingBean(ObjectWriter.class)
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
