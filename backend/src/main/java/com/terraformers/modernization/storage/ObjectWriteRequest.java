package com.terraformers.modernization.storage;

public record ObjectWriteRequest(
        String bucket,
        String key,
        String content,
        String contentType
) {
}
