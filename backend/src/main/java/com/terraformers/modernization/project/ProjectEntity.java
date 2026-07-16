package com.terraformers.modernization.project;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * Temporary compatibility projection for the simplified modernization APIs.
 *
 * <p>This is deliberately isolated from the canonical owner-based {@code projects}
 * aggregate. New domain logic must use the entities in the {@code projectcore}
 * package. This compatibility entity will be removed after the API adapters are
 * migrated.</p>
 */
@Entity
@Table(name = "project_metadata_compat")
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

    @Lob
    @Column(name = "terraform_draft", columnDefinition = "LONGTEXT")
    private String terraformDraft;

    @Column(name = "terraform_draft_updated_at")
    private Instant terraformDraftUpdatedAt;

    @Column(name = "source_bucket", length = 255)
    private String sourceBucket;

    @Column(name = "source_key", length = 1024)
    private String sourceKey;

    @Column(name = "source_storage_provider", length = 64)
    private String sourceStorageProvider;

    @Column(name = "source_binary_persisted", nullable = false)
    private boolean sourceBinaryPersisted;

    @Column(name = "source_etag", length = 255)
    private String sourceETag;

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

    public String getTerraformDraft() {
        return terraformDraft;
    }

    public void setTerraformDraft(String terraformDraft) {
        this.terraformDraft = terraformDraft;
    }

    public Instant getTerraformDraftUpdatedAt() {
        return terraformDraftUpdatedAt;
    }

    public void setTerraformDraftUpdatedAt(Instant terraformDraftUpdatedAt) {
        this.terraformDraftUpdatedAt = terraformDraftUpdatedAt;
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

    public String getSourceStorageProvider() {
        return sourceStorageProvider;
    }

    public void setSourceStorageProvider(String sourceStorageProvider) {
        this.sourceStorageProvider = sourceStorageProvider;
    }

    public boolean isSourceBinaryPersisted() {
        return sourceBinaryPersisted;
    }

    public void setSourceBinaryPersisted(boolean sourceBinaryPersisted) {
        this.sourceBinaryPersisted = sourceBinaryPersisted;
    }

    public String getSourceETag() {
        return sourceETag;
    }

    public void setSourceETag(String sourceETag) {
        this.sourceETag = sourceETag;
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
