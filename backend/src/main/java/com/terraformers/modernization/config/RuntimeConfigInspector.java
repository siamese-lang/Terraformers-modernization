package com.terraformers.modernization.config;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class RuntimeConfigInspector {

    private final RuntimeContractProperties properties;

    @Autowired
    public RuntimeConfigInspector(RuntimeContractProperties properties) {
        this.properties = properties;
    }

    public List<RuntimeConfigStatus> inspectRequiredEnv() {
        return properties.getRequiredEnv().stream()
                .map(name -> new RuntimeConfigStatus(name, hasText(System.getenv(name))))
                .toList();
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
