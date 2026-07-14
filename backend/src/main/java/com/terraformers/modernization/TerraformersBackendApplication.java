package com.terraformers.modernization;

import com.terraformers.modernization.config.RuntimeContractProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(RuntimeContractProperties.class)
public class TerraformersBackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(TerraformersBackendApplication.class, args);
    }
}
