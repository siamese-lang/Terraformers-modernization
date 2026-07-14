package com.terraformers.modernization.project;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TerraformDraftControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void uploadCreatesReadableProjectTerraformDraft() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "network.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("network"));

        mockMvc.perform(get("/api/projects/network/terraform/main.tf"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("network"))
                .andExpect(jsonPath("$.fileName").value("main.tf"))
                .andExpect(jsonPath("$.contentType").value("text/plain; charset=utf-8"))
                .andExpect(jsonPath("$.content").value(containsString("terraform")))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.draftUpdatedAt").isNotEmpty());
    }

    @Test
    void updateMainTfPersistsProjectDraftContent() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "app.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("app"));

        String updatedContent = "resource \\\"aws_s3_bucket\\\" \\\"example\\\" {}";
        String requestBody = "{\"content\":\"" + updatedContent + "\"}";

        mockMvc.perform(put("/api/projects/app/terraform/main.tf")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("app"))
                .andExpect(jsonPath("$.content").value("resource \"aws_s3_bucket\" \"example\" {}"))
                .andExpect(jsonPath("$.draftUpdatedAt").isNotEmpty());

        mockMvc.perform(get("/api/projects/app/terraform/main.tf"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value("resource \"aws_s3_bucket\" \"example\" {}"));
    }

    @Test
    void draftEndpointReturnsNotFoundForMissingProject() throws Exception {
        mockMvc.perform(get("/api/projects/missing-project/terraform/main.tf"))
                .andExpect(status().isNotFound());
    }
}
