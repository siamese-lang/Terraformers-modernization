package com.terraformers.modernization.analysis;

import jakarta.validation.Valid;
import java.net.URI;
import java.util.NoSuchElementException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/analysis/jobs")
public class AnalysisJobController {

    private final AnalysisJobService service;

    public AnalysisJobController(AnalysisJobService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<AnalysisJobResponse> create(@Valid @RequestBody AnalysisJobRequest request) {
        AnalysisJobResponse response = service.create(request);
        return ResponseEntity
                .created(URI.create("/api/analysis/jobs/" + response.id()))
                .body(response);
    }

    @GetMapping("/{id}")
    public AnalysisJobResponse get(@PathVariable String id) {
        return service.get(id);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<String> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.notFound().build();
    }
}
