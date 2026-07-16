package com.terraformers.modernization.identity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.oauth2.jwt.Jwt;

class AuthenticatedUserServiceTest {

    private UserRepository userRepository;
    private AuthenticatedUserService service;

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        service = new AuthenticatedUserService(userRepository);
    }

    @Test
    void createsUserFromAccessTokenWithoutEmailClaim() {
        Jwt accessToken = Jwt.withTokenValue("access-token")
                .header("alg", "none")
                .claim("sub", "cognito-access-sub")
                .claim("cognito:username", "terraformers-user")
                .claim("token_use", "access")
                .claim("client_id", "test-client")
                .build();

        when(userRepository.findByCognitoSub("cognito-access-sub"))
                .thenReturn(Optional.empty());
        when(userRepository.save(any(UserEntity.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        UserEntity created = service.getOrCreate(accessToken);

        ArgumentCaptor<UserEntity> captor = ArgumentCaptor.forClass(UserEntity.class);
        verify(userRepository).save(captor.capture());
        verify(userRepository, never()).findByEmail(any());

        assertThat(created).isSameAs(captor.getValue());
        assertThat(created.getCognitoSub()).isEqualTo("cognito-access-sub");
        assertThat(created.getEmail()).isNull();
        assertThat(created.getDisplayName()).isEqualTo("terraformers-user");
        assertThat(created.getRole()).isEqualTo(UserRole.USER);
        assertThat(created.getStatus()).isEqualTo(UserStatus.ACTIVE);
    }
}
