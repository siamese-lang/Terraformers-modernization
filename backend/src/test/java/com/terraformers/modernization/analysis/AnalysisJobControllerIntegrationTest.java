package com.terraformers.modernization.analysis;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest
@AutoConfigureMockMvc
@Import(SynchronousAnalysisExecutorTestConfig.class)
class AnalysisJobControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void createAnalysisJobReturnsSucceededStateAndResultArtifact() throws Exception {
        JsonNode upload = createOwnedProjectAndSourceFile();
        long projectId = upload.path("projectId").asLong();
        long sourceFileId = upload.path("sourceFileId").asLong();

        String requestBody = objectMapper.writeValueAsString(Map.of(
                "projectId", projectId,
                "sourceFileId", sourceFileId,
                "correlationId", "integration-smoke"
        ));

        MvcResult createResult = mockMvc.perform(post("/api/analysis/jobs")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestBody))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/analysis/jobs/")))
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.sourceFileId").value(sourceFileId))
                .andExpect(jsonPath("$.resultFileId").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.provider").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.resultObjectKey").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.resultPreview").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.failureReason").value(nullValue()))
                .andReturn();

        JsonNode created = objectMapper.readTree(createResult.getResponse().getContentAsString());
        String jobId = created.path("id").asText();

        mockMvc.perform(get("/api/analysis/jobs/{id}", jobId).with(testUserJwt()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(jobId))
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.sourceFileId").value(sourceFileId))
                .andExpect(jsonPath("$.resultFileId").isNumber())
                .andExpect(jsonPath("$.status").value("SUCCEEDED"))
                .andExpect(jsonPath("$.resultObjectKey", not(nullValue())))
                .andExpect(jsonPath("$.resultPreview", not(nullValue())));
    }

    private JsonNode createOwnedProjectAndSourceFile() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "integration-architecture.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        MvcResult uploadResult = mockMvc.perform(multipart("/api/upload")
                        .file(file)
                        .param("projectName", "Integration Project")
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").isNumber())
                .andExpect(jsonPath("$.sourceFileId").isNumber())
                .andReturn();
        return objectMapper.readTree(uploadResult.getResponse().getContentAsString());
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("analysis-controller-integration-user")
                .claim("email", "analysis-controller@example.com")
                .claim("name", "Analysis Controller User"));
    }
}
