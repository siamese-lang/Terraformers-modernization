# Frontend Stabilization Plan

## 1. Purpose

This project remains a backend and cloud infrastructure modernization portfolio.

Frontend work should be limited to stabilizing the existing Terraformers service flow so that backend/cloud improvements can be demonstrated through a usable screen.

The goal is not to rebuild the frontend, redesign the product, or claim frontend development as the main contribution.

## 2. Scope boundary

Frontend stabilization is in scope only when it supports one of these goals:

- user can sign up, sign in, and reach the main application screen;
- existing navigation elements do not lead to dead or broken flows;
- upload / analysis / result / project detail screens can exercise backend APIs;
- the UI does not block smoke or E2E validation;
- frontend runtime config points to the correct backend API and Cognito settings;
- obvious runtime errors are removed so the service can be demonstrated.

Out of scope:

- full frontend redesign;
- new design system;
- large UI feature expansion;
- frontend performance tuning unrelated to demo flow;
- claiming full frontend ownership;
- replacing backend/cloud work with UI polishing.

## 3. Known stabilization candidates

The following issues should be checked after the backend baseline is stable and frontend source is imported into the public-safe repository.

### 3.1 Signup black screen

Symptom:

- signup page or post-signup transition becomes a full black screen;
- user cannot complete onboarding or return to the application.

Likely areas:

- uncaught React runtime error;
- route guard redirect loop;
- missing Cognito runtime config;
- token parsing failure;
- CSS/theme overlay covering the page;
- error boundary missing.

Checks:

```bash
npm install
npm run build
npm run dev
```

Browser checks:

- DevTools Console error;
- Network tab for Cognito/API failure;
- route path after signup;
- local/session storage token state;
- React component stack if available.

### 3.2 Main screen icons not connected

Symptom:

- main screen displays icons/buttons;
- clicking them does nothing or routes to a missing page;
- upload/result/project navigation cannot be reached.

Likely areas:

- missing `onClick` handler;
- incorrect `Link` target;
- stale route names;
- component exists but API integration was never wired;
- disabled state is always true.

Checks:

- map each visible icon/button to a route or function;
- remove or hide dead controls that cannot be supported;
- prefer connecting existing backend-supported flows over adding new screens.

### 3.3 API base URL and auth mismatch

Symptom:

- UI loads but API calls fail;
- protected calls return 401/403;
- browser console shows CORS or `Unexpected token '<'` errors.

Likely areas:

- frontend API base URL points to the wrong host;
- CloudFront SPA fallback returns HTML for API requests;
- Authorization header is missing;
- Cognito user pool/client id mismatch;
- frontend expects old backend endpoint names.

Checks:

- inspect API base URL config;
- verify `/api/*` requests return JSON, not `index.html`;
- verify token is attached only where needed;
- align frontend request payloads with backend API contract.

## 4. Stabilization order

Do not start frontend work before backend local verification is stable.

Recommended order:

1. Backend Maven/test stabilization.
2. Backend local stub smoke success.
3. Runtime contract verification success.
4. Import public-safe frontend source.
5. Run frontend install/build.
6. Fix signup black screen first.
7. Fix main navigation dead controls.
8. Connect upload / analysis job / result object key flow to backend API.
9. Run browser smoke flow.
10. Update validation evidence.

## 5. Browser smoke flow

Minimum flow to support:

```text
Open app
  -> sign up or sign in
  -> reach main screen
  -> upload architecture image or select sample input
  -> create analysis job
  -> show job status
  -> show result preview or result object key
  -> open project detail
```

If full Cognito signup is unstable during local testing, keep a documented local/dev bypass only if it is clearly separated from production runtime and never presented as the real auth flow.

## 6. Evidence to keep

Keep sanitized screenshots or logs for:

- frontend build success;
- signup/signin path reaching main screen;
- main screen controls connected to routes or intentionally hidden;
- analysis job request from browser;
- API response with `SUCCEEDED`, `resultObjectKey`, and `resultPreview`;
- browser console free of blocking runtime errors during the smoke flow.

## 7. Portfolio explanation

```text
프론트엔드는 본인의 핵심 기여로 과장하지 않고, 기존 팀 프로젝트 화면이 백엔드·클라우드 고도화 결과를 시연할 수 있도록 막힌 흐름을 복구하는 범위에서 안정화했습니다. 회원가입 후 검은 화면, 연결되지 않은 메인 화면 아이콘, API base URL과 인증 설정 불일치처럼 E2E 검증을 막는 문제를 확인하고, backend analysis job 흐름을 화면에서 확인할 수 있는 수준으로 정리했습니다.
```
