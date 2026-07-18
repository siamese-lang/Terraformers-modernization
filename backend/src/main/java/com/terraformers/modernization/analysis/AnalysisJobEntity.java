package com.terraformers.modernization.analysis;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "analysis_jobs")
public class AnalysisJobEntity {

    @Id
    @Column(length = 36, nullable = false, updatable = false)
    private String id;

    @Column(name = "project_id", nullable = false)
    private Long projectId;

    @Column(name = "source_file_id", nullable = false)
    private Long sourceFileId;

    @Column(name = "result_file_id")
    private Long resultFileId;

    @Column(name = "source_bucket", nullable = false, length = 255)
    private String sourceBucket;

    @Column(name = "source_key", nullable = false, length = 1024)
    private String sourceKey;

    @Column(name = "correlation_id", length = 128)
    private String correlationId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private AnalysisJobStatus status = AnalysisJobStatus.PENDING;

    @Enumerated(EnumType.STRING)
    @Column(name = "analysis_mode", nullable = false, length = 32)
    private AnalysisMode analysisMode = AnalysisMode.INTEGRATED_JAVA;

    @Column(length = 64)
    private String provider;

    @Column(name = "result_object_key", length = 1024)
    private String resultObjectKey;

    @Column(name = "result_preview", columnDefinition = "TEXT")
    private String resultPreview;

    @Column(name = "analysis_summary", columnDefinition = "TEXT")
    private String analysisSummary;

    @Column(name = "detected_components", columnDefinition = "TEXT")
    private String detectedComponents;

    @Column(name = "detected_relationships", columnDefinition = "TEXT")
    private String detectedRelationships;

    @Column(name = "analysis_warnings", columnDefinition = "TEXT")
    private String analysisWarnings;

    @Column(name = "failure_reason", length = 2000)
    private String failureReason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }

    public String getId() {
        return id;
    }

    public Long getProjectId() {
        return projectId;
    }

    public void setProjectId(Long projectId) {
        this.projectId = projectId;
    }

    public Long getSourceFileId() {
        return sourceFileId;
    }

    public void setSourceFileId(Long sourceFileId) {
        this.sourceFileId = sourceFileId;
    }

    public Long getResultFileId() {
        return resultFileId;
    }

    public void setResultFileId(Long resultFileId) {
        this.resultFileId = resultFileId;
    }

    public String getSourceBucket() {
        return sourceBucket;
    }

    public void setSourceBucket(String sourceBucket) {
        this.sourceBucket = sourceBucket;
    }

    public String getSourceKey() {
        return sourceKey;
    }

    public void setSourceKey(String sourceKey) {
        this.sourceKey = sourceKey;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public void setCorrelationId(String correlationId) {
        this.correlationId = correlationId;
    }

    public AnalysisJobStatus getStatus() {
        return status;
    }

    public void setStatus(AnalysisJobStatus status) {
        this.status = status;
    }

    public AnalysisMode getAnalysisMode() {
        return analysisMode;
    }

    public void setAnalysisMode(AnalysisMode analysisMode) {
        this.analysisMode = analysisMode;
    }

    public String getProvider() {
        return provider;
    }

    public void setProvider(String provider) {
        this.provider = provider;
    }

    public String getResultObjectKey() {
        return resultObjectKey;
    }

    public void setResultObjectKey(String resultObjectKey) {
        this.resultObjectKey = resultObjectKey;
    }

    public String getResultPreview() {
        return resultPreview;
    }

    public void setResultPreview(String resultPreview) {
        this.resultPreview = resultPreview;
    }

    public String getAnalysisSummary() { return analysisSummary; }
    public void setAnalysisSummary(String analysisSummary) { this.analysisSummary = analysisSummary; }
    public String getDetectedComponents() { return detectedComponents; }
    public void setDetectedComponents(String detectedComponents) { this.detectedComponents = detectedComponents; }
    public String getDetectedRelationships() { return detectedRelationships; }
    public void setDetectedRelationships(String detectedRelationships) { this.detectedRelationships = detectedRelationships; }
    public String getAnalysisWarnings() { return analysisWarnings; }
    public void setAnalysisWarnings(String analysisWarnings) { this.analysisWarnings = analysisWarnings; }

    public String getFailureReason() {
        return failureReason;
    }

    public void setFailureReason(String failureReason) {
        this.failureReason = failureReason;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
