package com.terraformers.modernization.project;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
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
class ProjectMetadataControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void uploadCreatesQueryableProjectMetadata() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "Project Tree Diagram.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("project-tree-diagram"));

        mockMvc.perform(get("/api/projects/project-tree-diagram"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("project-tree-diagram"))
                .andExpect(jsonPath("$.displayName").value("Project Tree Diagram"))
                .andExpect(jsonPath("$.visibility").value("PRIVATE"))
                .andExpect(jsonPath("$.latestAnalysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.latestResultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.sourceKey").value(startsWith("browser-uploads/project-tree-diagram/")))
                .andExpect(jsonPath("$.originalFilename").value("Project Tree Diagram.png"))
                .andExpect(jsonPath("$.contentType").value("image/png"))
                .andExpect(jsonPath("$.uploadSizeBytes").value(16));
    }

    @Test
    void visibilityCanBeUpdatedAndListedAsPublic() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "Public Project.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("public-project"));

        mockMvc.perform(patch("/api/projects/public-project/visibility")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"PUBLIC\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("public-project"))
                .andExpect(jsonPath("$.visibility").value("PUBLIC"));

        mockMvc.perform(get("/api/projects/public"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].projectId").value("public-project"))
                .andExpect(jsonPath("$[0].visibility").value("PUBLIC"));
    }

    @Test
    void unknownProjectReturnsNotFound() throws Exception {
        mockMvc.perform(get("/api/projects/missing-project"))
                .andExpect(status().isNotFound());
    }
}
