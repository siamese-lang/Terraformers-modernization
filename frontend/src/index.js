import React from 'react';
import ReactDOM from 'react-dom/client';
import { Amplify } from 'aws-amplify';
import App from './App';
import './index.css';
import { buildAmplifyConfig, logCognitoConfigSummary } from './awsConfig';

const awsConfig = buildAmplifyConfig();
logCognitoConfigSummary(awsConfig, process.env.NODE_ENV);

if (awsConfig) {
  Amplify.configure(awsConfig);
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
