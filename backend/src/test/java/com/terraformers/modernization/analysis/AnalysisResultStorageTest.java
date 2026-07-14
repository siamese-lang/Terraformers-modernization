package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.storage.ObjectWriteResult;
import com.terraformers.modernization.storage.StubObjectWriter;
import java.util.List;
import org.junit.jupiter.api.Test;

class AnalysisResultStorageTest {

    @Test
    void storesTerraformDraftAndReturnsGeneratedObjectKey() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setResultBucketName("result-bucket");
        properties.setResultKeyPrefix("custom-prefix/");

        AnalysisResultStorage storage = new AnalysisResultStorage(new StubObjectWriter(), properties);
        AnalysisJobEntity job = new AnalysisJobEntity();
        job.setProjectId("project-1");
        job.setSourceBucket("source-bucket");
        job.setSourceKey("uploads/diagram.png");
        job.prePersist();

        ObjectWriteResult writeResult = storage.storeTerraformDraft(job, new AnalysisResult(
                "stub",
                "provider \"aws\" {}",
                "explanation",
                List.of("reference-1")
        ));

        assertThat(writeResult.bucket()).isEqualTo("result-bucket");
        assertThat(writeResult.key()).startsWith("custom-prefix/project-1/");
        assertThat(writeResult.key()).endsWith("/" + job.getId() + "/main.tf");
    }

    @Test
    void fallsBackToSourceBucketWhenResultBucketIsNotConfigured() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        AnalysisResultStorage storage = new AnalysisResultStorage(new StubObjectWriter(), properties);
        AnalysisJobEntity job = new AnalysisJobEntity();
        job.setProjectId("project-2");
        job.setSourceBucket("source-bucket");
        job.setSourceKey("uploads/diagram.png");
        job.prePersist();

        ObjectWriteResult writeResult = storage.storeTerraformDraft(job, new AnalysisResult(
                "stub",
                "provider \"aws\" {}",
                "explanation",
                List.of()
        ));

        assertThat(writeResult.bucket()).isEqualTo("source-bucket");
        assertThat(writeResult.key()).startsWith("analysis-results/project-2/");
    }
}
