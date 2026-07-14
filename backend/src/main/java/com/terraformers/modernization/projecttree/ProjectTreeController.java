package com.terraformers.modernization.projecttree;

import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/project-tree")
public class ProjectTreeController {

    private final ProjectTreeService service;

    public ProjectTreeController(ProjectTreeService service) {
        this.service = service;
    }

    @GetMapping
    public List<ProjectTreeNode> listTrees() {
        return service.listTrees();
    }

    @GetMapping("/{projectId}")
    public ProjectTreeResponse getTree(@PathVariable String projectId) {
        return service.getTree(projectId);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Void> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
