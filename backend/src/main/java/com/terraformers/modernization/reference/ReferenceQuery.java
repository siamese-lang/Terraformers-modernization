package com.terraformers.modernization.reference;

import java.util.List;

public record ReferenceQuery(
        String projectId,
        String sourceBucket,
        String sourceKey,
        String contentType,
        List<String> detectedServices,
        int limit
) {
    public static ReferenceQuery fromObject(
            String projectId,
            String sourceBucket,
            String sourceKey,
            String contentType
    ) {
        return new ReferenceQuery(
                projectId,
                sourceBucket,
                sourceKey,
                contentType,
                List.of(),
                3
        );
    }
}
