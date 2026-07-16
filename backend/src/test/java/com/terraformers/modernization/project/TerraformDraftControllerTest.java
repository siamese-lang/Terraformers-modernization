package com.terraformers.modernization.project;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisJobRepository;
import com.terraformers.modernization.collaboration.BoardRepository;
import com.terraformers.modernization.collaboration.CommentRepository;
import com.terraformers.modernization.identity.UserRepository;
import com.terraformers.modernization.projectcore.OwnedProjectRepository;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TerraformDraftControllerTest {

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
    void uploadCreatesReadableProjectTerraformArtifact() throws Exception {
        Long projectId = upload("network.png");

        mockMvc.perform(get("/api/projects/" + projectId + "/terraform/main.tf").with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.fileId").isNumber())
                .andExpect(jsonPath("$.fileName").value("main.tf"))
                .andExpect(jsonPath("$.contentType").value("text/plain; charset=utf-8"))
                .andExpect(jsonPath("$.content").value(containsString("terraform")))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.draftUpdatedAt").isNotEmpty());
    }

    @Test
    void updateMainTfPersistsCanonicalArtifactContent() throws Exception {
        Long projectId = upload("app.png");
        String updatedContent = "resource \"aws_s3_bucket\" \"example\" {}";
        String requestBody = objectMapper.writeValueAsString(Map.of("content", updatedContent));

        mockMvc.perform(put("/api/projects/" + projectId + "/terraform/main.tf")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.content").value(updatedContent))
                .andExpect(jsonPath("$.draftUpdatedAt").isNotEmpty());

        mockMvc.perform(get("/api/projects/" + projectId + "/terraform/main.tf").with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value(updatedContent));
    }

    @Test
    void updateMainTfRequiresAuthentication() throws Exception {
        Long projectId = upload("private-app.png");

        mockMvc.perform(put("/api/projects/" + projectId + "/terraform/main.tf")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"terraform {}\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void draftEndpointReturnsNotFoundForMissingProject() throws Exception {
        mockMvc.perform(get("/api/projects/999999/terraform/main.tf").with(testUserJwt()))
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
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andReturn();
        JsonNode response = objectMapper.readTree(result.getResponse().getContentAsString());
        return response.get("projectId").asLong();
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("draft-test-user")
                .claim("email", "draft@example.com")
                .claim("name", "Draft User"));
    }
}
