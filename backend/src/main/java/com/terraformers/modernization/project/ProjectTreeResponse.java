package com.terraformers.modernization.project;

import java.time.Instant;
import java.util.List;

public record ProjectTreeResponse(
        String projectId,
        String name,
        String path,
        String type,
        List<ProjectTreeNode> children,
        String terraformDraftApiPath,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        String sourceBucket,
        String sourceKey,
        Instant projectUpdatedAt
) {
    static ProjectTreeResponse from(ProjectResponse project) {
        String projectId = project.projectId();
        String terraformDraftApiPath = "/api/projects/" + projectId + "/terraform/main.tf";
        ProjectTreeNode mainTf = new ProjectTreeNode(
                "main.tf",
                "main.tf",
                "file",
                "text/plain; charset=utf-8",
                terraformDraftApiPath,
                List.of()
        );

        return new ProjectTreeResponse(
                projectId,
                project.displayName(),
                projectId,
                "directory",
                List.of(mainTf),
                terraformDraftApiPath,
                project.latestAnalysisJobId(),
                project.latestResultObjectKey(),
                project.sourceBucket(),
                project.sourceKey(),
                project.updatedAt()
        );
    }
}
