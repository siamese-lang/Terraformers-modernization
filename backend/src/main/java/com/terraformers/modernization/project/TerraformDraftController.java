package com.terraformers.modernization.project;

import jakarta.validation.Valid;
import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/projects/{projectId}/terraform")
public class TerraformDraftController {

    private final ProjectMetadataService projectMetadataService;

    public TerraformDraftController(ProjectMetadataService projectMetadataService) {
        this.projectMetadataService = projectMetadataService;
    }

    @GetMapping("/main.tf")
    public TerraformDraftResponse getMainTf(@PathVariable String projectId) {
        return projectMetadataService.getTerraformDraft(projectId);
    }

    @PutMapping("/main.tf")
    public TerraformDraftResponse updateMainTf(
            @PathVariable String projectId,
            @Valid @RequestBody TerraformDraftUpdateRequest request
    ) {
        return projectMetadataService.updateTerraformDraft(projectId, request.content());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
