package com.terraformers.modernization.config;

import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "terraformers.runtime")
public class RuntimeContractProperties {

    private List<String> requiredEnv = new ArrayList<>(List.of(
            "SPRING_DATASOURCE_URL",
            "SPRING_DATASOURCE_USERNAME",
            "SPRING_DATASOURCE_PASSWORD",
            "COGNITO_REGION",
            "COGNITO_USER_POOL_ID",
            "COGNITO_USER_POOL_CLIENT_ID",
            "COGNITO_JWKS_URL",
            "S3_BUCKET_NAME",
            "AI_LOG_QUEUE_URL",
            "TERRAFORM_LOG_QUEUE_URL"
    ));

    public List<String> getRequiredEnv() {
        return requiredEnv;
    }

    public void setRequiredEnv(List<String> requiredEnv) {
        this.requiredEnv = requiredEnv;
    }
}
