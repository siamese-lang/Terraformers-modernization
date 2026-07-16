package com.terraformers.modernization.security;

import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class CognitoJwtSecurityConfig {

    @Bean
    @ConditionalOnProperty(name = "terraformers.security.jwt.enabled", havingValue = "true")
    SecurityFilterChain cognitoSecurityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/upload").authenticated()
                        .requestMatchers(HttpMethod.POST, "/api/analysis/jobs").authenticated()
                        .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                        .anyRequest().permitAll())
                .oauth2ResourceServer(resourceServer -> resourceServer.jwt(Customizer.withDefaults()))
                .httpBasic(httpBasic -> httpBasic.disable())
                .formLogin(formLogin -> formLogin.disable());
        return http.build();
    }

    @Bean
    @ConditionalOnProperty(
            name = "terraformers.security.jwt.enabled",
            havingValue = "false",
            matchIfMissing = true
    )
    SecurityFilterChain localPermitAllSecurityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .cors(Customizer.withDefaults())
                .authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll())
                .httpBasic(httpBasic -> httpBasic.disable())
                .formLogin(formLogin -> formLogin.disable());
        return http.build();
    }

    @Bean
    @ConditionalOnProperty(name = "terraformers.security.jwt.enabled", havingValue = "true")
    JwtDecoder cognitoJwtDecoder(
            @Value("${terraformers.security.jwt.issuer-uri}") String issuerUri,
            @Value("${terraformers.security.jwt.jwk-set-uri}") String jwkSetUri,
            @Value("${terraformers.security.jwt.client-id}") String clientId
    ) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        OAuth2TokenValidator<Jwt> issuerValidator = JwtValidators.createDefaultWithIssuer(issuerUri);
        OAuth2TokenValidator<Jwt> cognitoClaimsValidator = jwt -> validateCognitoClaims(jwt, clientId);
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(issuerValidator, cognitoClaimsValidator));
        return decoder;
    }

    private OAuth2TokenValidatorResult validateCognitoClaims(Jwt jwt, String clientId) {
        String tokenUse = jwt.getClaimAsString("token_use");
        if (!List.of("id", "access").contains(tokenUse)) {
            return failure("invalid_token_use", "Cognito token_use must be id or access");
        }

        String accessTokenClientId = jwt.getClaimAsString("client_id");
        boolean clientMatches = clientId.equals(accessTokenClientId) || jwt.getAudience().contains(clientId);
        if (!clientMatches) {
            return failure("invalid_client", "Cognito token client does not match configured client id");
        }
        return OAuth2TokenValidatorResult.success();
    }

    private OAuth2TokenValidatorResult failure(String code, String description) {
        return OAuth2TokenValidatorResult.failure(new OAuth2Error(code, description, null));
    }
}
