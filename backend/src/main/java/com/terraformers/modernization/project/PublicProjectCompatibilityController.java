package com.terraformers.modernization.project;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PublicProjectCompatibilityController {

    private final ProjectMetadataService service;

    public PublicProjectCompatibilityController(ProjectMetadataService service) {
        this.service = service;
    }

    @GetMapping("/api/public-projects")
    public List<PublicProjectResponse> listPublicProjects() {
        return service.listPublic().stream()
                .map(PublicProjectResponse::from)
                .toList();
    }
}
