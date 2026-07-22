package com.terraformers.modernization.storage;

import java.time.Instant;

public record SourceObjectReadResponse(
        Long projectId,
        Long sourceFileId,
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
