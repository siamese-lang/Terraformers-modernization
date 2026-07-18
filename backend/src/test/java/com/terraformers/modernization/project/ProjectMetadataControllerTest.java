package com.terraformers.modernization.project;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisJobRepository;
import com.terraformers.modernization.analysis.SynchronousAnalysisExecutorTestConfig;
import com.terraformers.modernization.collaboration.BoardRepository;
import com.terraformers.modernization.collaboration.CommentRepository;
import com.terraformers.modernization.identity.UserRepository;
import com.terraformers.modernization.projectcore.OwnedProjectRepository;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest
@AutoConfigureMockMvc
@Import(SynchronousAnalysisExecutorTestConfig.class)
@ActiveProfiles("test")
class ProjectMetadataControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private CommentRepository commentRepository;

    @Autowired
    private BoardRepository boardRepository;

    @Autowired
    private AnalysisJobRepository analysisJobRepository;

    @Autowired
    private ProjectFileRepository projectFileRepository;

    @Autowired
    private OwnedProjectRepository projectRepository;

    @Autowired
    private UserRepository userRepository;

    @BeforeEach
    void cleanState() {
        commentRepository.deleteAll();
        boardRepository.deleteAll();
        analysisJobRepository.deleteAll();
        projectFileRepository.deleteAll();
        projectRepository.deleteAll();
        userRepository.deleteAll();
    }

    @Test
    void uploadCreatesQueryableCanonicalProjectMetadata() throws Exception {
        Long projectId = upload("Project Tree Diagram.png");

        mockMvc.perform(get("/api/projects/" + projectId).with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.displayName").value("Project Tree Diagram"))
                .andExpect(jsonPath("$.visibility").value("PRIVATE"))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultFileId").isNumber())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.sourceFileId").isNumber())
                .andExpect(jsonPath("$.sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.sourceKey").value(startsWith("browser-uploads/" + projectId + "/")))
                .andExpect(jsonPath("$.sourceStorageProvider").value("metadata-only"))
                .andExpect(jsonPath("$.sourceBinaryPersisted").value(false))
                .andExpect(jsonPath("$.originalFilename").value("Project Tree Diagram.png"))
                .andExpect(jsonPath("$.contentType").value("image/png"))
                .andExpect(jsonPath("$.uploadSizeBytes").value(16));
    }

    @Test
    void metadataOnlySourceObjectReadReturnsConflictForOwner() throws Exception {
        Long projectId = upload("Project Source.png");

        mockMvc.perform(get("/api/projects/" + projectId + "/source-object").with(testUserJwt()))
                .andExpect(status().isConflict());
    }

    @Test
    void visibilityCanBeUpdatedAndListedAsPublic() throws Exception {
        Long projectId = upload("Public Project.png");
        publishProject(projectId);

        mockMvc.perform(get("/api/projects/public"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].projectId").value(projectId))
                .andExpect(jsonPath("$[0].visibility").value("PUBLIC"));

        mockMvc.perform(get("/api/projects/" + projectId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId));
    }

    @Test
    void publicProjectsCompatibilityListsOnlyPublicProjects() throws Exception {
        upload("Private Design.png");
        Long publicProjectId = upload("Shared Architecture.png");
        publishProject(publicProjectId);

        mockMvc.perform(get("/api/public-projects"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value(publicProjectId))
                .andExpect(jsonPath("$[0].id").value(publicProjectId))
                .andExpect(jsonPath("$[0].projectName").value("Shared Architecture"))
                .andExpect(jsonPath("$[0].name").value("Shared Architecture"))
                .andExpect(jsonPath("$[0].visibility").value("PUBLIC"))
                .andExpect(jsonPath("$[0].isPrivate").value(false))
                .andExpect(jsonPath("$[0].sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$[0].sourceKey").value(startsWith("browser-uploads/" + publicProjectId + "/")))
                .andExpect(jsonPath("$[0].sourceStorageProvider").value("metadata-only"))
                .andExpect(jsonPath("$[0].sourceBinaryPersisted").value(false))
                .andExpect(jsonPath("$[0].latestResultFileId").isNumber())
                .andExpect(jsonPath("$[0].projectTreeApiPath").value("/api/project-tree/" + publicProjectId))
                .andExpect(jsonPath("$[0].terraformDraftApiPath")
                        .value("/api/projects/" + publicProjectId + "/terraform/main.tf"));
    }

    @Test
    void ownedProjectListRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/projects"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void unknownProjectReturnsNotFound() throws Exception {
        mockMvc.perform(get("/api/projects/999999").with(testUserJwt()))
                .andExpect(status().isNotFound());
    }

    @Test
    void ownerCanDeleteProjectAndDeletedProjectIsExcludedFromOwnedList() throws Exception {
        Long projectId = upload("Delete Me.png");

        mockMvc.perform(delete("/api/projects/" + projectId).with(testUserJwt()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/projects").with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));

        mockMvc.perform(get("/api/projects/" + projectId).with(testUserJwt()))
                .andExpect(status().isNotFound());
    }

    @Test
    void nonOwnerCannotDeletePrivateProject() throws Exception {
        Long projectId = upload("Private Delete Target.png");

        mockMvc.perform(delete("/api/projects/" + projectId).with(otherUserJwt()))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/projects/" + projectId).with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId));
    }

    private Long upload(String filename) throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                filename,
                "image/png",
                "fake image bytes".getBytes()
        );

        MvcResult result = mockMvc.perform(multipart("/api/upload")
                        .file(file)
                        .param("projectName", filename.replace(".png", ""))
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").isNumber())
                .andReturn();

        JsonNode response = objectMapper.readTree(result.getResponse().getContentAsString());
        return response.get("projectId").asLong();
    }

    private void publishProject(Long projectId) throws Exception {
        mockMvc.perform(patch("/api/projects/" + projectId + "/visibility")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"PUBLIC\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.visibility").value("PUBLIC"));
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("metadata-test-user")
                .claim("email", "metadata@example.com")
                .claim("name", "Metadata User"));
    }

    private RequestPostProcessor otherUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("metadata-other-user")
                .claim("email", "other-metadata@example.com")
                .claim("name", "Other Metadata User"));
    }
}
