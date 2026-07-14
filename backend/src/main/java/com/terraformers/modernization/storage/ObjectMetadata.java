package com.terraformers.modernization.storage;

public record ObjectMetadata(
        String bucket,
        String key,
        String contentType,
        long contentLength,
        String eTag
) {
}
