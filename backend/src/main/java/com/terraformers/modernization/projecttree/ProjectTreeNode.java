package com.terraformers.modernization.projecttree;

import java.util.List;

public record ProjectTreeNode(
        String id,
        String name,
        String type,
        String projectId,
        String parentId,
        boolean isLeaf,
        boolean isPrivate,
        String apiPath,
        String sourceBucket,
        String sourceKey,
        String resultObjectKey,
        List<ProjectTreeNode> children
) {
    public static ProjectTreeNode project(
            String projectId,
            String name,
            boolean isPrivate,
            List<ProjectTreeNode> children
    ) {
        return new ProjectTreeNode(
                projectId,
                name,
                "project",
                projectId,
                null,
                false,
                isPrivate,
                null,
                null,
                null,
                null,
                children
        );
    }

    public static ProjectTreeNode folder(String id, String name, String projectId, String parentId, List<ProjectTreeNode> children) {
        return new ProjectTreeNode(
                id,
                name,
                "folder",
                projectId,
                parentId,
                false,
                false,
                null,
                null,
                null,
                null,
                children
        );
    }

    public static ProjectTreeNode file(
            String id,
            String name,
            String projectId,
            String parentId,
            String apiPath,
            String sourceBucket,
            String sourceKey,
            String resultObjectKey
    ) {
        return new ProjectTreeNode(
                id,
                name,
                "file",
                projectId,
                parentId,
                true,
                false,
                apiPath,
                sourceBucket,
                sourceKey,
                resultObjectKey,
                List.of()
        );
    }
}
