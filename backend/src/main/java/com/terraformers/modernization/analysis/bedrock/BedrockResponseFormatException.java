package com.terraformers.modernization.analysis.bedrock;

public class BedrockResponseFormatException extends RuntimeException {

    public BedrockResponseFormatException(String message) {
        super(message);
    }

    public BedrockResponseFormatException(String message, Throwable cause) {
        super(message, cause);
    }
}
