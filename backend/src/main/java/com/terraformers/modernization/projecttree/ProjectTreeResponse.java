package com.terraformers.modernization.projecttree;

import java.time.Instant;
import java.util.List;

public record ProjectTreeResponse(
        String projectId,
        String displayName,
        String visibility,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        Instant updatedAt,
        List<ProjectTreeNode> tree
) {
}
