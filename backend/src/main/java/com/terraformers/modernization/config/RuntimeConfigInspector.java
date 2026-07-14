package com.terraformers.modernization.config;

import java.util.List;
import java.util.function.Function;
import org.springframework.stereotype.Service;

@Service
public class RuntimeConfigInspector {

    private final RuntimeContractProperties properties;
    private final Function<String, String> envSupplier;

    public RuntimeConfigInspector(RuntimeContractProperties properties) {
        this(properties, System::getenv);
    }

    RuntimeConfigInspector(RuntimeContractProperties properties, Function<String, String> envSupplier) {
        this.properties = properties;
        this.envSupplier = envSupplier;
    }

    public List<RuntimeConfigStatus> inspectRequiredEnv() {
        return properties.getRequiredEnv().stream()
                .map(name -> new RuntimeConfigStatus(name, hasText(envSupplier.apply(name))))
                .toList();
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
