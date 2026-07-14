package com.terraformers.modernization.project;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "projects")
public class ProjectEntity {

    @Id
    @Column(name = "project_id", length = 64, nullable = false, updatable = false)
    private String projectId;

    @Column(name = "display_name", nullable = false, length = 160)
    private String displayName;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private ProjectVisibility visibility = ProjectVisibility.PRIVATE;

    @Column(name = "latest_analysis_job_id", length = 36)
    private String latestAnalysisJobId;

    @Column(name = "latest_result_object_key", length = 1024)
    private String latestResultObjectKey;

    @Column(name = "source_bucket", length = 255)
    private String sourceBucket;

    @Column(name = "source_key", length = 1024)
    private String sourceKey;

    @Column(name = "original_filename", length = 255)
    private String originalFilename;

    @Column(name = "content_type", length = 128)
    private String contentType;

    @Column(name = "upload_size_bytes")
    private Long uploadSizeBytes;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }

    public String getProjectId() {
        return projectId;
    }

    public void setProjectId(String projectId) {
        this.projectId = projectId;
    }

    public String getDisplayName() {
        return displayName;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    public ProjectVisibility getVisibility() {
        return visibility;
    }

    public void setVisibility(ProjectVisibility visibility) {
        this.visibility = visibility;
    }

    public String getLatestAnalysisJobId() {
        return latestAnalysisJobId;
    }

    public void setLatestAnalysisJobId(String latestAnalysisJobId) {
        this.latestAnalysisJobId = latestAnalysisJobId;
    }

    public String getLatestResultObjectKey() {
        return latestResultObjectKey;
    }

    public void setLatestResultObjectKey(String latestResultObjectKey) {
        this.latestResultObjectKey = latestResultObjectKey;
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

    public String getOriginalFilename() {
        return originalFilename;
    }

    public void setOriginalFilename(String originalFilename) {
        this.originalFilename = originalFilename;
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
    }

    public Long getUploadSizeBytes() {
        return uploadSizeBytes;
    }

    public void setUploadSizeBytes(Long uploadSizeBytes) {
        this.uploadSizeBytes = uploadSizeBytes;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
