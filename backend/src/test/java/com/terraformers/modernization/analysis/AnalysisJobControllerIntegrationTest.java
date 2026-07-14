package com.terraformers.modernization.analysis;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
class AnalysisJobControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void createAnalysisJobReturnsSucceededStateAndResultObjectKey() throws Exception {
        String requestBody = """
                {
                  "projectId": "project-smoke",
                  "sourceBucket": "example-bucket",
                  "sourceKey": "uploads/architecture-diagram.png",
                  "correlationId": "integration-smoke"
                }
                """;

        MvcResult createResult = mockMvc.perform(post("/api/analysis/jobs")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestBody))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/api/analysis/jobs/")))
                .andExpect(jsonPath("$.status").value("SUCCEEDED"))
                .andExpect(jsonPath("$.provider").value("stub-integrated-java"))
                .andExpect(jsonPath("$.resultObjectKey", not(nullValue())))
                .andExpect(jsonPath("$.resultPreview", not(nullValue())))
                .andExpect(jsonPath("$.failureReason").doesNotExist())
                .andReturn();

        JsonNode created = objectMapper.readTree(createResult.getResponse().getContentAsString());
        String jobId = created.path("id").asText();

        mockMvc.perform(get("/api/analysis/jobs/{id}", jobId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(jobId))
                .andExpect(jsonPath("$.status").value("SUCCEEDED"))
                .andExpect(jsonPath("$.resultObjectKey").value(created.path("resultObjectKey").asText()))
                .andExpect(jsonPath("$.resultPreview", not(nullValue())));
    }
}
