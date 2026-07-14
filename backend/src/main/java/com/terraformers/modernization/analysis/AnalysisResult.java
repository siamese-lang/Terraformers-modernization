package com.terraformers.modernization.analysis;

import java.util.List;

public record AnalysisResult(
        String provider,
        String terraformCode,
        String explanation,
        List<String> references
) {
    public String preview() {
        String text = terraformCode == null ? "" : terraformCode.strip();
        if (text.length() <= 500) {
            return text;
        }
        return text.substring(0, 500) + "...";
    }
}
