package com.terraformers.modernization.storage;

public record ObjectWriteResult(
        String bucket,
        String key,
        String eTag
) {
    public String objectUri() {
        return "s3://" + bucket + "/" + key;
    }
}
