package com.terraformers.modernization.analysis.bedrock;

import java.util.List;

public record ParsedBedrockAnalysis(
        String terraformCode,
        String explanation,
        List<String> components,
        List<String> relationships,
        List<String> warnings
) {
}
