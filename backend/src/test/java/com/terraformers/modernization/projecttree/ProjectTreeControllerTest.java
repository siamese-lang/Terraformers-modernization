package com.terraformers.modernization.projecttree;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
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
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest
@AutoConfigureMockMvc
@Import(SynchronousAnalysisExecutorTestConfig.class)
@ActiveProfiles("test")
class ProjectTreeControllerTest {

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
    void projectTreeReturnsSourceAndGeneratedTerraformArtifactsAfterUpload() throws Exception {
        Long projectId = upload("AWS아키텍처.png");
        String id = String.valueOf(projectId);

        mockMvc.perform(get("/api/project-tree/" + projectId).with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.displayName").value("AWS아키텍처"))
                .andExpect(jsonPath("$.visibility").value("PRIVATE"))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultFileId").isNumber())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.tree[0].id").value(id))
                .andExpect(jsonPath("$.tree[0].name").value("AWS아키텍처"))
                .andExpect(jsonPath("$.tree[0].type").value("project"))
                .andExpect(jsonPath("$.tree[0].isPrivate").value(true))
                .andExpect(jsonPath("$.tree[0].children[0].id").value(id + ":source"))
                .andExpect(jsonPath("$.tree[0].children[0].name").value("source"))
                .andExpect(jsonPath("$.tree[0].children[0].type").value("folder"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].type").value("file"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].name").value("AWS아키텍처.png"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].sourceKey")
                        .value(startsWith("browser-uploads/" + projectId + "/")))
                .andExpect(jsonPath("$.tree[0].children[1].id").value(id + ":terraform"))
                .andExpect(jsonPath("$.tree[0].children[1].name").value("terraform"))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].name").value("main.tf"))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].apiPath")
                        .value("/api/projects/" + projectId + "/terraform/main.tf"))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].resultObjectKey").isNotEmpty());
    }

    @Test
    void projectTreeListReturnsOwnedRootNodesForAuthenticatedUser() throws Exception {
        upload("network.png");

        mockMvc.perform(get("/api/project-tree").with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].projectId").isNumber())
                .andExpect(jsonPath("$[0].type").value("project"))
                .andExpect(jsonPath("$[0].children[0].type").value("folder"));
    }

    @Test
    void projectTreeListRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/project-tree"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void projectTreeReturnsNotFoundForMissingProject() throws Exception {
        mockMvc.perform(get("/api/project-tree/999999").with(testUserJwt()))
                .andExpect(status().isNotFound());
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
                .andReturn();
        JsonNode response = objectMapper.readTree(result.getResponse().getContentAsString());
        return response.get("projectId").asLong();
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("tree-test-user")
                .claim("email", "tree@example.com")
                .claim("name", "Tree User"));
    }
}
