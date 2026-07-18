package com.terraformers.modernization.analysis.bedrock;

import java.util.List;

public record ParsedBedrockAnalysis(
        String terraformCode,
        String summary,
        List<String> components,
        List<String> relationships,
        List<String> warnings
) {
}
