package com.terraformers.modernization.analysis;

import java.util.List;

public record AnalysisResult(
        String provider,
        String terraformCode,
        String explanation,
        List<String> components,
        List<String> relationships,
        List<String> warnings,
        List<String> references
) {
    public AnalysisResult withTerraformCode(String sanitizedTerraformCode) {
        return new AnalysisResult(provider, sanitizedTerraformCode, explanation, components, relationships, warnings, references);
    }

    public String preview() {
        String text = terraformCode == null ? "" : terraformCode.strip();
        if (text.length() <= 500) {
            return text;
        }
        return text.substring(0, 500) + "...";
    }
}
