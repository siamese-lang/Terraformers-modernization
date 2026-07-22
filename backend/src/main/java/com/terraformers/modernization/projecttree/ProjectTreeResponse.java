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
        String analysisStatus,
        String analysisSummary,
        List<String> detectedComponents,
        List<String> detectedRelationships,
        List<String> warnings,
        Instant updatedAt,
        List<ProjectTreeNode> tree
) {
}
