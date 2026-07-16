package com.terraformers.modernization.projectcore;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.project.ProjectVisibility;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ProjectDomainServiceTest {

    private OwnedProjectRepository projectRepository;
    private ProjectFileRepository fileRepository;
    private ProjectDomainService service;

    @BeforeEach
    void setUp() {
        projectRepository = mock(OwnedProjectRepository.class);
        fileRepository = mock(ProjectFileRepository.class);
        service = new ProjectDomainService(projectRepository, fileRepository);
    }

    @Test
    void createsOwnerBasedPrivateProjectByDefault() {
        UserEntity owner = mock(UserEntity.class);
        when(owner.getUserId()).thenReturn(42L);
        when(projectRepository.save(any(OwnedProjectEntity.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        OwnedProjectEntity created = service.createProject(
                owner,
                "  Architecture Review  ",
                "Modernized Terraformers project",
                null
        );

        assertThat(created.getOwner()).isSameAs(owner);
        assertThat(created.getName()).isEqualTo("Architecture Review");
        assertThat(created.getDescription()).isEqualTo("Modernized Terraformers project");
        assertThat(created.getVisibility()).isEqualTo(ProjectVisibility.PRIVATE);
        assertThat(created.getStatus()).isEqualTo(ProjectStatus.ACTIVE);
        verify(projectRepository).save(created);
    }

    @Test
    void rejectsImplicitProjectCreationWithoutPersistedOwner() {
        UserEntity owner = mock(UserEntity.class);
        when(owner.getUserId()).thenReturn(null);

        assertThatThrownBy(() -> service.createProject(owner, "project", null, ProjectVisibility.PUBLIC))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("persisted user is required");
    }
}
