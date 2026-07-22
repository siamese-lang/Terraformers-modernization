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
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest
@AutoConfigureMockMvc
@Import(SynchronousAnalysisExecutorTestConfig.class)
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
                .andExpect(jsonPath("$.authorDisplayName").value("Comment User"))
                .andExpect(jsonPath("$.userEmail").value("c***@example.com"))
                .andExpect(jsonPath("$.createdAt").isNotEmpty());

        mockMvc.perform(get("/api/projects/" + projectId + "/comments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].projectId").value(projectId))
                .andExpect(jsonPath("$[0].content").value("첫 번째 공개 댓글"))
                .andExpect(jsonPath("$[0].authorDisplayName").value("Comment User"))
                .andExpect(jsonPath("$[0].userEmail").value("c***@example.com"));
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
                .andExpect(jsonPath("$.authorDisplayName").value("Comment User"))
                .andExpect(jsonPath("$.userEmail").value("c***@example.com"));

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

    @Test
    void uuidDisplayNameIsNotReturnedAsPublicAuthorName() throws Exception {
        Long projectId = upload("UUID Comment.png");
        publishProject(projectId);
        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .with(jwt().jwt(builder -> builder.subject("c468bd6c-e001-70a9-e0d2-31d6bcde9501")
                                .claim("email", "uuid@example.com")))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"content\":\"safe\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.authorDisplayName").value("u***@example.com"))
                .andExpect(jsonPath("$.authorDisplayName").value(org.hamcrest.Matchers.not("c468bd6c-e001-70a9-e0d2-31d6bcde9501")));
    }

    @Test
    void emailDisplayNameIsMaskedInsteadOfBeingPublished() throws Exception {
        Long projectId = upload("Email Comment.png");
        publishProject(projectId);
        mockMvc.perform(post("/api/projects/" + projectId + "/comments")
                        .with(jwt().jwt(builder -> builder.subject("email-name-user")
                                .claim("email", "same@example.com").claim("name", "same@example.com")))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"content\":\"safe\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.authorDisplayName").value("s***@example.com"));
    }

    @Test
    void displayNameEndpointTrimsAndValidatesAuthenticatedUser() throws Exception {
        mockMvc.perform(patch("/api/users/me/display-name").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"Name\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(patch("/api/users/me/display-name").with(testUserJwt()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"  Nickname  \"}"))
                .andExpect(status().isNoContent());
        mockMvc.perform(patch("/api/users/me/display-name").with(testUserJwt()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"   \"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(patch("/api/users/me/display-name").with(testUserJwt()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"" + "x".repeat(101) + "\"}"))
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
                        .param("projectName", filename.replace(".png", ""))
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
