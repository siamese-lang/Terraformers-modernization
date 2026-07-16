package com.terraformers.modernization.projecttree;

import java.time.Instant;
import java.util.List;

public record ProjectTreeResponse(
        Long projectId,
        String displayName,
        String visibility,
        String latestAnalysisJobId,
        Long latestResultFileId,
        String latestResultObjectKey,
        Instant updatedAt,
        List<ProjectTreeNode> tree
) {
}
