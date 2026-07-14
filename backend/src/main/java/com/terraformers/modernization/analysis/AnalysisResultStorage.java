package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.ObjectWriteRequest;
import com.terraformers.modernization.storage.ObjectWriteResult;
import com.terraformers.modernization.storage.ObjectWriter;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import org.springframework.stereotype.Service;

@Service
public class AnalysisResultStorage {

    private static final DateTimeFormatter DATE_PATH = DateTimeFormatter.ofPattern("yyyy/MM/dd")
            .withZone(ZoneOffset.UTC);

    private final ObjectWriter objectWriter;
    private final AnalysisRuntimeProperties properties;

    public AnalysisResultStorage(ObjectWriter objectWriter, AnalysisRuntimeProperties properties) {
        this.objectWriter = objectWriter;
        this.properties = properties;
    }

    public ObjectWriteResult storeTerraformDraft(AnalysisJobEntity job, AnalysisResult result) {
        String bucket = resolveResultBucket(job);
        String key = buildResultKey(job);
        return objectWriter.writeText(new ObjectWriteRequest(
                bucket,
                key,
                result.terraformCode(),
                "text/plain; charset=utf-8"
        ));
    }

    private String resolveResultBucket(AnalysisJobEntity job) {
        if (properties.getResultBucketName() != null && !properties.getResultBucketName().isBlank()) {
            return properties.getResultBucketName();
        }
        return job.getSourceBucket();
    }

    private String buildResultKey(AnalysisJobEntity job) {
        String prefix = normalizePrefix(properties.getResultKeyPrefix());
        String datePath = DATE_PATH.format(Instant.now());
        return prefix + "/" + job.getProjectId() + "/" + datePath + "/" + job.getId() + "/main.tf";
    }

    private String normalizePrefix(String prefix) {
        if (prefix == null || prefix.isBlank()) {
            return "analysis-results";
        }
        String normalized = prefix.strip();
        while (normalized.startsWith("/")) {
            normalized = normalized.substring(1);
        }
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized.isBlank() ? "analysis-results" : normalized;
    }
}
