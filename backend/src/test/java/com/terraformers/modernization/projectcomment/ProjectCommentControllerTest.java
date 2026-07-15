package com.terraformers.modernization.projectcomment;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.terraformers.modernization.project.ProjectRepository;
import org.junit.jupiter.api.BeforeEach;
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
class ProjectCommentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ProjectRepository projectRepository;

    @Autowired
    private ProjectCommentRepository commentRepository;

    @BeforeEach
    void cleanState() {
        commentRepository.deleteAll();
        projectRepository.deleteAll();
    }

    @Test
    void publicProjectCommentsCanBeCreatedAndListedThroughModernEndpoint() throws Exception {
        createProject("Shared Architecture.png", "shared-architecture");
        publishProject("shared-architecture");

        mockMvc.perform(post("/api/projects/shared-architecture/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"첫 번째 공개 댓글\",\"userEmail\":\"user@example.com\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value("shared-architecture"))
                .andExpect(jsonPath("$.content").value("첫 번째 공개 댓글"))
                .andExpect(jsonPath("$.userEmail").value("user@example.com"))
                .andExpect(jsonPath("$.createdAt").isNotEmpty());

        mockMvc.perform(get("/api/projects/shared-architecture/comments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value("shared-architecture"))
                .andExpect(jsonPath("$[0].content").value("첫 번째 공개 댓글"))
                .andExpect(jsonPath("$[0].userEmail").value("user@example.com"));
    }

    @Test
    void publicProjectCommentsCompatibilityEndpointsKeepOriginalFrontendContract() throws Exception {
        createProject("Community Diagram.png", "community-diagram");
        publishProject("community-diagram");

        mockMvc.perform(post("/api/addProjectComment")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"projectId\":\"community-diagram\",\"content\":\"호환 댓글\",\"userEmail\":\"compat@example.com\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value("community-diagram"))
                .andExpect(jsonPath("$.content").value("호환 댓글"));

        mockMvc.perform(get("/api/getProjectComments/community-diagram"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value("community-diagram"))
                .andExpect(jsonPath("$[0].content").value("호환 댓글"))
                .andExpect(jsonPath("$[0].userEmail").value("compat@example.com"));
    }

    @Test
    void privateProjectCommentsAreRejected() throws Exception {
        createProject("Private Design.png", "private-design");

        mockMvc.perform(get("/api/projects/private-design/comments"))
                .andExpect(status().isForbidden());

        mockMvc.perform(post("/api/projects/private-design/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"비공개 댓글은 허용하지 않음\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void missingProjectCommentsReturnNotFound() throws Exception {
        mockMvc.perform(get("/api/projects/missing-project/comments"))
                .andExpect(status().isNotFound());
    }

    @Test
    void blankCommentContentIsRejected() throws Exception {
        createProject("Public Blank.png", "public-blank");
        publishProject("public-blank");

        mockMvc.perform(post("/api/projects/public-blank/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"   \"}"))
                .andExpect(status().isBadRequest());
    }

    private void createProject(String filename, String expectedProjectId) throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                filename,
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value(expectedProjectId));
    }

    private void publishProject(String projectId) throws Exception {
        mockMvc.perform(patch("/api/projects/" + projectId + "/visibility")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"PUBLIC\"}"))
                .andExpect(status().isOk());
    }
}
