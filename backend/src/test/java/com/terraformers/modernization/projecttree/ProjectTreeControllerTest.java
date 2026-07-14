package com.terraformers.modernization.projecttree;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ProjectTreeControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void projectTreeReturnsReadOnlySourceAndTerraformNodesAfterUpload() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "AWS아키텍처.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("aws"));

        mockMvc.perform(get("/api/project-tree/aws"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("aws"))
                .andExpect(jsonPath("$.displayName").value("AWS아키텍처"))
                .andExpect(jsonPath("$.visibility").value("PRIVATE"))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.tree[0].id").value("aws"))
                .andExpect(jsonPath("$.tree[0].name").value("AWS아키텍처"))
                .andExpect(jsonPath("$.tree[0].type").value("project"))
                .andExpect(jsonPath("$.tree[0].isPrivate").value(true))
                .andExpect(jsonPath("$.tree[0].children[0].id").value("aws:source"))
                .andExpect(jsonPath("$.tree[0].children[0].name").value("source"))
                .andExpect(jsonPath("$.tree[0].children[0].type").value("folder"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].type").value("file"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].name").value("AWS아키텍처.png"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.tree[0].children[0].children[0].sourceKey").value(startsWith("browser-uploads/aws/")))
                .andExpect(jsonPath("$.tree[0].children[1].id").value("aws:terraform"))
                .andExpect(jsonPath("$.tree[0].children[1].name").value("terraform"))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].name").value("main.tf"))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].apiPath").value(startsWith("/api/analysis/jobs/")))
                .andExpect(jsonPath("$.tree[0].children[1].children[0].resultObjectKey").isNotEmpty());
    }

    @Test
    void projectTreeListReturnsRootNodesForAllProjects() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "network.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("network"));

        mockMvc.perform(get("/api/project-tree"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].type").value("project"))
                .andExpect(jsonPath("$[0].children[0].type").value("folder"));
    }

    @Test
    void projectTreeReturnsNotFoundForMissingProject() throws Exception {
        mockMvc.perform(get("/api/project-tree/missing-project"))
                .andExpect(status().isNotFound());
    }
}
