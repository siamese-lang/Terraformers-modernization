package com.terraformers.modernization.project;

import java.time.Instant;

public record TerraformDraftResponse(
        String projectId,
        String fileName,
        String contentType,
        String content,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        Instant draftUpdatedAt,
        Instant projectUpdatedAt
) {
    static TerraformDraftResponse from(ProjectEntity entity) {
        return new TerraformDraftResponse(
                entity.getProjectId(),
                "main.tf",
                "text/plain; charset=utf-8",
                entity.getTerraformDraft() == null ? "" : entity.getTerraformDraft(),
                entity.getLatestAnalysisJobId(),
                entity.getLatestResultObjectKey(),
                entity.getTerraformDraftUpdatedAt(),
                entity.getUpdatedAt()
        );
    }
}
