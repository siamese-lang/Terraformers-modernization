package com.terraformers.modernization.project;

import java.util.List;

public record ProjectTreeNode(
        String name,
        String path,
        String type,
        String contentType,
        String apiPath,
        List<ProjectTreeNode> children
) {
}
