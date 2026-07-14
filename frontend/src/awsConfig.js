const requiredConfigKeys = [
  'REACT_APP_AWS_REGION',
  'REACT_APP_COGNITO_USER_POOL_ID',
  'REACT_APP_COGNITO_USER_POOL_CLIENT_ID',
];

const getValue = (name) => process.env[name]?.trim();

export function buildAmplifyConfig() {
  const missing = requiredConfigKeys.filter((key) => !getValue(key));

  if (missing.length > 0) {
    return null;
  }

  return {
    Auth: {
      Cognito: {
        userPoolId: getValue('REACT_APP_COGNITO_USER_POOL_ID'),
        userPoolClientId: getValue('REACT_APP_COGNITO_USER_POOL_CLIENT_ID'),
        loginWith: {
          email: true,
        },
      },
    },
  };
}

export function logCognitoConfigSummary(config, nodeEnv) {
  if (!config) {
    console.info('[auth] Cognito browser configuration is not set. Auth routes will render, but sign-in/sign-up require .env.local values.');
    return;
  }

  console.info('[auth] Cognito browser configuration loaded.', {
    nodeEnv,
    region: getValue('REACT_APP_AWS_REGION'),
    hasUserPoolId: Boolean(config.Auth?.Cognito?.userPoolId),
    hasUserPoolClientId: Boolean(config.Auth?.Cognito?.userPoolClientId),
  });
}
