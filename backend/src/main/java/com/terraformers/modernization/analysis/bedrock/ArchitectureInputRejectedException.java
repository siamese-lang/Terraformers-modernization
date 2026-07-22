package com.terraformers.modernization.analysis.bedrock;

public class ArchitectureInputRejectedException extends RuntimeException {

    private final ArchitectureInputType inputType;
    private final Double classificationConfidence;

    public ArchitectureInputRejectedException(ArchitectureInputType inputType, Double classificationConfidence) {
        super("Bedrock input was rejected: " + inputType);
        if (inputType == ArchitectureInputType.ARCHITECTURE_DIAGRAM) {
            throw new IllegalArgumentException("architecture diagrams must not be rejected");
        }
        this.inputType = inputType;
        this.classificationConfidence = classificationConfidence;
    }

    public ArchitectureInputType getInputType() {
        return inputType;
    }

    public Double getClassificationConfidence() {
        return classificationConfidence;
    }
}
