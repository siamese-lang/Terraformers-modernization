package com.terraformers.modernization.projectcomment;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
class ProjectCommentControllerTest {

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
    void publicProjectCommentsUseAuthenticatedBoardAndCommentDomain() throws Exception {
        Long projectId = upload("Shared Architecture.png");
        publishProject(projectId);

        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"첫 번째 공개 댓글\",\"userEmail\":\"spoof@example.com\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.content").value("첫 번째 공개 댓글"))
                .andExpect(jsonPath("$.userEmail").value("comment@example.com"))
                .andExpect(jsonPath("$.createdAt").isNotEmpty());

        mockMvc.perform(get("/api/projects/" + projectId + "/comments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value(projectId))
                .andExpect(jsonPath("$[0].content").value("첫 번째 공개 댓글"))
                .andExpect(jsonPath("$[0].userEmail").value("comment@example.com"));
    }

    @Test
    void compatibilityEndpointsKeepNamesButUseNumericIdsAndAuthenticatedAuthor() throws Exception {
        Long projectId = upload("Community Diagram.png");
        publishProject(projectId);

        mockMvc.perform(post("/api/addProjectComment")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"projectId\":" + projectId
                                + ",\"content\":\"호환 댓글\",\"userEmail\":\"spoof@example.com\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.projectId").value(projectId))
                .andExpect(jsonPath("$.content").value("호환 댓글"))
                .andExpect(jsonPath("$.userEmail").value("comment@example.com"));

        mockMvc.perform(get("/api/getProjectComments/" + projectId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value(projectId))
                .andExpect(jsonPath("$[0].content").value("호환 댓글"));
    }

    @Test
    void commentCreationRequiresAuthentication() throws Exception {
        Long projectId = upload("Auth Required.png");
        publishProject(projectId);

        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"인증 필요\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void privateProjectCommentsAreRejected() throws Exception {
        Long projectId = upload("Private Design.png");

        mockMvc.perform(get("/api/projects/" + projectId + "/comments"))
                .andExpect(status().isForbidden());

        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"비공개 댓글은 허용하지 않음\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void missingProjectCommentsReturnNotFound() throws Exception {
        mockMvc.perform(get("/api/projects/999999/comments"))
                .andExpect(status().isNotFound());
    }

    @Test
    void blankCommentContentIsRejected() throws Exception {
        Long projectId = upload("Public Blank.png");
        publishProject(projectId);

        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"   \"}"))
                .andExpect(status().isBadRequest());
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

    private void publishProject(Long projectId) throws Exception {
        mockMvc.perform(patch("/api/projects/" + projectId + "/visibility")
                        .with(testUserJwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"PUBLIC\"}"))
                .andExpect(status().isOk());
    }

    private RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("comment-test-user")
                .claim("email", "comment@example.com")
                .claim("name", "Comment User"));
    }
}
