package com.terraformers.modernization.storage;

public record ObjectContent(
        ObjectMetadata metadata,
        byte[] bytes
) {
    public int size() {
        return bytes == null ? 0 : bytes.length;
    }
}
