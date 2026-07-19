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
    private boolean bedrockProviderEnabled;
    private boolean bedrockEmbeddingEnabled;
    private int bedrockMaxTokens = 8192;
    private boolean opensearchRetrieverEnabled;
    private int opensearchTopK = 3;
    private String opensearchServiceName = "aoss";
    private String resultBucketName;
    private String resultKeyPrefix = "analysis-results";
    private boolean sqsPublisherEnabled;
    private String progressQueueUrl;
    private String resultQueueUrl;

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

    public boolean isBedrockProviderEnabled() {
        return bedrockProviderEnabled;
    }

    public void setBedrockProviderEnabled(boolean bedrockProviderEnabled) {
        this.bedrockProviderEnabled = bedrockProviderEnabled;
    }

    public boolean isBedrockEmbeddingEnabled() {
        return bedrockEmbeddingEnabled;
    }

    public void setBedrockEmbeddingEnabled(boolean bedrockEmbeddingEnabled) {
        this.bedrockEmbeddingEnabled = bedrockEmbeddingEnabled;
    }

    public int getBedrockMaxTokens() {
        return bedrockMaxTokens;
    }

    public void setBedrockMaxTokens(int bedrockMaxTokens) {
        this.bedrockMaxTokens = bedrockMaxTokens;
    }

    public boolean isOpensearchRetrieverEnabled() {
        return opensearchRetrieverEnabled;
    }

    public void setOpensearchRetrieverEnabled(boolean opensearchRetrieverEnabled) {
        this.opensearchRetrieverEnabled = opensearchRetrieverEnabled;
    }

    public int getOpensearchTopK() {
        return opensearchTopK;
    }

    public void setOpensearchTopK(int opensearchTopK) {
        this.opensearchTopK = opensearchTopK;
    }

    public String getOpensearchServiceName() {
        return opensearchServiceName;
    }

    public void setOpensearchServiceName(String opensearchServiceName) {
        this.opensearchServiceName = opensearchServiceName;
    }

    public String getResultBucketName() {
        return resultBucketName;
    }

    public void setResultBucketName(String resultBucketName) {
        this.resultBucketName = resultBucketName;
    }

    public String getResultKeyPrefix() {
        return resultKeyPrefix;
    }

    public void setResultKeyPrefix(String resultKeyPrefix) {
        this.resultKeyPrefix = resultKeyPrefix;
    }

    public boolean isSqsPublisherEnabled() {
        return sqsPublisherEnabled;
    }

    public void setSqsPublisherEnabled(boolean sqsPublisherEnabled) {
        this.sqsPublisherEnabled = sqsPublisherEnabled;
    }

    public String getProgressQueueUrl() {
        return progressQueueUrl;
    }

    public void setProgressQueueUrl(String progressQueueUrl) {
        this.progressQueueUrl = progressQueueUrl;
    }

    public String getResultQueueUrl() {
        return resultQueueUrl;
    }

    public void setResultQueueUrl(String resultQueueUrl) {
        this.resultQueueUrl = resultQueueUrl;
    }
}
