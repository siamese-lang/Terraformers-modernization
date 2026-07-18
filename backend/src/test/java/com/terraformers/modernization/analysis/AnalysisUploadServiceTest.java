package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.project.ProjectVisibility;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.storage.UploadObjectStorageService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.oauth2.jwt.Jwt;

class AnalysisUploadServiceTest {

    @Test
    void newlyCreatedProjectIsSoftDeletedWhenDownstreamStorageFails() {
        AuthenticatedUserService authenticatedUserService = mock(AuthenticatedUserService.class);
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService projectArtifactService = mock(ProjectArtifactService.class);
        UploadObjectStorageService storageService = mock(UploadObjectStorageService.class);
        AnalysisJobService analysisJobService = mock(AnalysisJobService.class);
        UserEntity currentUser = mock(UserEntity.class);
        OwnedProjectEntity project = mock(OwnedProjectEntity.class);
        Jwt jwt = mock(Jwt.class);
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "diagram.png",
                "image/png",
                "fake image bytes".getBytes()
        );
        when(authenticatedUserService.getOrCreate(jwt)).thenReturn(currentUser);
        when(project.getProjectId()).thenReturn(77L);
        when(projectDomainService.createProject(currentUser, "New Project", null, ProjectVisibility.PRIVATE))
                .thenReturn(project);
        when(storageService.store(any(), any(), any())).thenThrow(new IllegalStateException("storage unavailable"));
        AnalysisUploadService service = new AnalysisUploadService(
                authenticatedUserService,
                projectDomainService,
                projectArtifactService,
                storageService,
                analysisJobService
        );

        assertThatThrownBy(() -> service.upload(file, null, "New Project", jwt))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("storage unavailable");
        verify(projectDomainService).softDelete(77L, currentUser);
    }
}
