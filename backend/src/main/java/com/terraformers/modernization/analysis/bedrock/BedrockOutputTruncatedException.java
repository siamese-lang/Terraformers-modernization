package com.terraformers.modernization.analysis.bedrock;

public class BedrockOutputTruncatedException extends RuntimeException {

    private final String stopReason;
    private final Integer outputTokens;

    public BedrockOutputTruncatedException() {
        this("max_tokens", null);
    }

    public BedrockOutputTruncatedException(String stopReason, Integer outputTokens) {
        super("Bedrock output was truncated before analysis completed");
        this.stopReason = stopReason;
        this.outputTokens = outputTokens;
    }

    public String getStopReason() {
        return stopReason;
    }

    public Integer getOutputTokens() {
        return outputTokens;
    }
}
