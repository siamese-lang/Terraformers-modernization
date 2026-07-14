package com.terraformers.modernization.web;

import com.terraformers.modernization.config.RuntimeConfigInspector;
import com.terraformers.modernization.config.RuntimeConfigStatus;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/runtime")
public class RuntimeReadinessController {

    private final RuntimeConfigInspector runtimeConfigInspector;

    public RuntimeReadinessController(RuntimeConfigInspector runtimeConfigInspector) {
        this.runtimeConfigInspector = runtimeConfigInspector;
    }

    @GetMapping("/required-config")
    public List<RuntimeConfigStatus> requiredConfig() {
        return runtimeConfigInspector.inspectRequiredEnv();
    }
}
