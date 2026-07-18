package com.terraformers.modernization.analysis;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
class AnalysisUploadControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void uploadCreatesOwnedProjectSourceAndTerraformArtifacts() throws Exception {
        MockMultipartFile file = image("AWS아키텍처.png");

        mockMvc.perform(multipart("/api/upload")
                        .file(file)
                        .param("projectName", "Architecture Upload")
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", startsWith("/api/analysis/jobs/")))
                .andExpect(jsonPath("$.uploadMode").value("owned-project-analysis"))
                .andExpect(jsonPath("$.storageProvider").value("metadata-only"))
                .andExpect(jsonPath("$.binaryPersisted").value(false))
                .andExpect(jsonPath("$.analysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.projectId").isNumber())
                .andExpect(jsonPath("$.sourceFileId").isNumber())
                .andExpect(jsonPath("$.resultFileId").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.sourceKey").value(startsWith("browser-uploads/")))
                .andExpect(jsonPath("$.originalFilename").value("AWS아키텍처.png"))
                .andExpect(jsonPath("$.contentType").value("image/png"))
                .andExpect(jsonPath("$.size").value(16))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.provider").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.resultObjectKey").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.resultPreview").value(org.hamcrest.Matchers.nullValue()));
    }

    @Test
    void analysisJobPollingRequiresAuthenticatedProjectAccess() throws Exception {
        MvcResult uploadResult = mockMvc.perform(multipart("/api/upload")
                        .file(image("polling.png"))
                        .param("projectName", "Polling Project")
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andReturn();
        JsonNode upload = objectMapper.readTree(uploadResult.getResponse().getContentAsString());
        String jobId = upload.get("analysisJobId").asText();

        mockMvc.perform(get("/api/analysis/jobs/" + jobId))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/analysis/jobs/" + jobId).with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(jobId))
                .andExpect(jsonPath("$.projectId").value(upload.get("projectId").asLong()))
                .andExpect(jsonPath("$.sourceFileId").isNumber())
                .andExpect(jsonPath("$.resultFileId").isNumber())
                .andExpect(jsonPath("$.status").value("SUCCEEDED"));
    }

    @Test
    void uploadRequiresAuthentication() throws Exception {
        mockMvc.perform(multipart("/api/upload").file(image("architecture.png")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void uploadRejectsEmptyFileForAuthenticatedUser() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "empty.png",
                "image/png",
                new byte[0]
        );

        mockMvc.perform(multipart("/api/upload")
                        .file(file)
                        .param("projectName", "Empty File Project")
                        .with(testUserJwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().string("file must not be empty"));
    }

    @Test
    void uploadAddsImageToExistingProjectWhenProjectIdIsProvided() throws Exception {
        MvcResult firstUpload = mockMvc.perform(multipart("/api/upload")
                        .file(image("first.png"))
                        .param("projectName", "Existing Target")
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andReturn();
        long projectId = objectMapper.readTree(firstUpload.getResponse().getContentAsString()).path("projectId").asLong();

        mockMvc.perform(multipart("/api/upload")
                        .file(image("second.png"))
                        .param("projectId", String.valueOf(projectId))
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.originalFilename").value("second.png"));
    }

    @Test
    void uploadRejectsAmbiguousProjectMode() throws Exception {
        mockMvc.perform(multipart("/api/upload")
                        .file(image("missing-mode.png"))
                        .with(testUserJwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("exactly one mode")));

        mockMvc.perform(multipart("/api/upload")
                        .file(image("both-modes.png"))
                        .param("projectName", "Both")
                        .param("projectId", "1")
                        .with(testUserJwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("exactly one mode")));
    }

    private MockMultipartFile image(String filename) {
        return new MockMultipartFile(
                "file",
                filename,
                "image/png",
                "fake image bytes".getBytes()
        );
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("test-cognito-sub")
                .claim("email", "user@example.com")
                .claim("name", "Test User"));
    }
}
