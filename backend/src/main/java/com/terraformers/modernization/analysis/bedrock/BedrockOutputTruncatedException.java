package com.terraformers.modernization.analysis.bedrock;

public class BedrockOutputTruncatedException extends RuntimeException {

    public BedrockOutputTruncatedException() {
        super("Bedrock output was truncated before analysis completed");
    }
}
