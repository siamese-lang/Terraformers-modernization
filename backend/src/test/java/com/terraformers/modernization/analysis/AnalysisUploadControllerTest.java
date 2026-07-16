package com.terraformers.modernization.analysis;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
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
class AnalysisUploadControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void uploadCreatesOwnedProjectFileAndAnalysisJob() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "AWS아키텍처.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload")
                        .file(file)
                        .with(testUserJwt()))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", startsWith("/api/analysis/jobs/")))
                .andExpect(jsonPath("$.uploadMode").value("owned-project-analysis"))
                .andExpect(jsonPath("$.storageProvider").value("metadata-only"))
                .andExpect(jsonPath("$.binaryPersisted").value(false))
                .andExpect(jsonPath("$.analysisJobId").isNotEmpty())
                .andExpect(jsonPath("$.projectId").isNumber())
                .andExpect(jsonPath("$.sourceFileId").isNumber())
                .andExpect(jsonPath("$.sourceBucket").value("example-bucket"))
                .andExpect(jsonPath("$.sourceKey").value(startsWith("browser-uploads/")))
                .andExpect(jsonPath("$.originalFilename").value("AWS아키텍처.png"))
                .andExpect(jsonPath("$.contentType").value("image/png"))
                .andExpect(jsonPath("$.size").value(16))
                .andExpect(jsonPath("$.status").value("SUCCEEDED"))
                .andExpect(jsonPath("$.provider").value("stub-integrated-java"))
                .andExpect(jsonPath("$.resultObjectKey").isNotEmpty())
                .andExpect(jsonPath("$.resultPreview").isNotEmpty());
    }

    @Test
    void uploadRequiresAuthentication() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "architecture.png",
                "image/png",
                "fake image bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
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
                        .with(testUserJwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().string("file must not be empty"));
    }

    private org.springframework.test.web.servlet.request.RequestPostProcessor testUserJwt() {
        return jwt().jwt(builder -> builder
                .subject("test-cognito-sub")
                .claim("email", "user@example.com")
                .claim("name", "Test User"));
    }
}
