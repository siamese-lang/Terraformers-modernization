package com.terraformers.modernization.project;

import com.terraformers.modernization.analysis.AnalysisJobEntity;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import java.time.Instant;

public record TerraformDraftResponse(
        Long projectId,
        Long fileId,
        String fileName,
        String contentType,
        String content,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        Instant draftUpdatedAt,
        Instant projectUpdatedAt
) {
    static TerraformDraftResponse from(
            OwnedProjectEntity project,
            ProjectFileEntity terraformFile,
            AnalysisJobEntity latestJob
    ) {
        return new TerraformDraftResponse(
                project.getProjectId(),
                terraformFile.getFileId(),
                terraformFile.getOriginalFilename() == null ? "main.tf" : terraformFile.getOriginalFilename(),
                terraformFile.getContentType(),
                terraformFile.getInlineContent() == null ? "" : terraformFile.getInlineContent(),
                latestJob == null ? null : latestJob.getId(),
                terraformFile.getS3Key(),
                terraformFile.getUpdatedAt(),
                project.getUpdatedAt()
        );
    }
}
