package com.terraformers.modernization.analysis;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "terraformers.analysis")
public class AnalysisRuntimeProperties {

    private AnalysisMode mode = AnalysisMode.INTEGRATED_JAVA;
    private String bedrockModelId;
    private String bedrockEmbeddingModelId;
    private String opensearchEndpoint;
    private String indexName;
    private String vectorFieldName;
    private String contentFieldName;
    private String externalPythonServiceUrl;

    public AnalysisMode getMode() {
        return mode;
    }

    public void setMode(AnalysisMode mode) {
        this.mode = mode;
    }

    public String getBedrockModelId() {
        return bedrockModelId;
    }

    public void setBedrockModelId(String bedrockModelId) {
        this.bedrockModelId = bedrockModelId;
    }

    public String getBedrockEmbeddingModelId() {
        return bedrockEmbeddingModelId;
    }

    public void setBedrockEmbeddingModelId(String bedrockEmbeddingModelId) {
        this.bedrockEmbeddingModelId = bedrockEmbeddingModelId;
    }

    public String getOpensearchEndpoint() {
        return opensearchEndpoint;
    }

    public void setOpensearchEndpoint(String opensearchEndpoint) {
        this.opensearchEndpoint = opensearchEndpoint;
    }

    public String getIndexName() {
        return indexName;
    }

    public void setIndexName(String indexName) {
        this.indexName = indexName;
    }

    public String getVectorFieldName() {
        return vectorFieldName;
    }

    public void setVectorFieldName(String vectorFieldName) {
        this.vectorFieldName = vectorFieldName;
    }

    public String getContentFieldName() {
        return contentFieldName;
    }

    public void setContentFieldName(String contentFieldName) {
        this.contentFieldName = contentFieldName;
    }

    public String getExternalPythonServiceUrl() {
        return externalPythonServiceUrl;
    }

    public void setExternalPythonServiceUrl(String externalPythonServiceUrl) {
        this.externalPythonServiceUrl = externalPythonServiceUrl;
    }
}
