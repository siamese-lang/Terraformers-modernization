package com.terraformers.modernization.storage;

import java.time.Instant;

public record SourceObjectReadResponse(
        String projectId,
        String sourceBucket,
        String sourceKey,
        String storageProvider,
        boolean binaryPersisted,
        String sourceETag,
        String s3ETag,
        Long contentLength,
        String contentType,
        Instant lastModified
) {
}
