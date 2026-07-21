# Last Verified Live Evidence Before Teardown

## 1. Evidence scope

This document records the latest verified live runtime state observed before portfolio teardown planning. It is a bounded evidence summary, not a replacement for the final read-only parity check immediately before deletion.

The runtime evidence below was captured after PR #86 and before later documentation-only commits. Documentation merges do not by themselves prove the current Argo CD revision, so the final pre-teardown check must refresh the revision field while preserving the verified workload facts.

## 2. Backend delivery identity

| Field | Verified value |
|---|---|
| Backend source SHA | `d39acc4a489fc5e22023281343283609501a36f9` |
| Immutable image tag | `git-d39acc4a489fc5e22023281343283609501a36f9` |
| ECR digest | `sha256:2f4a177a06d1e64819b06240a441e619105980e43dea04b3f4709a86e2d95c73` |
| Runtime image | `024863981627.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend@sha256:2f4a177a06d1e64819b06240a441e619105980e43dea04b3f4709a86e2d95c73` |
| Last verified Argo CD revision | `fbb057b2890109469d49d6e00e47d5734cb20244` |
| Argo CD sync | `Synced` |
| Argo CD health | `Healthy` |

The Argo CD revision must be refreshed before teardown because later documentation-only commits advanced the integration branch without changing the Backend manifest or image digest.

## 3. Backend Pod and health

Verified Pod state after the Pod-level non-root UID fix:

```text
pod_uid=10001
ready=true
restarts=0
init_containers=opentelemetry-auto-instrumentation-java
init_status=Completed
health={"status":"UP","groups":["liveness","readiness"]}
```

Verified injected runtime configuration included:

- `JAVA_TOOL_OPTIONS`;
- `OTEL_SERVICE_NAME`;
- `OTEL_RESOURCE_ATTRIBUTES`;
- `OTEL_AWS_APPLICATION_SIGNALS_ENABLED`;
- `OTEL_AWS_APP_SIGNALS_ENABLED`;
- OTLP traces, metrics, and logs endpoints;
- IRSA regional STS and web-identity variables.

This proved that the CloudWatch Agent Operator selected the Backend workload and successfully injected the Java auto-instrumentation init container.

## 4. Actual analysis and observability result

One real browser analysis completed successfully before evidence capture.

Summary:

```text
analysis_outcomes=succeeded started
aoss_metric_series=1
application_signals_latency_series=78
xray_trace_count=181
xray_terraformers_service_count=2
operations_visibility_result=PASS
```

The original X-Ray count command returned paginated counts as multiple lines (`159`, `22`, `0`, `0`). Their sum is 181. The shell integer-comparison error affected only the summary script; it did not invalidate the trace data.

The evidence proves:

- analysis-start and analysis-success custom metrics were emitted;
- an AOSS retrieval metric series existed;
- Application Signals latency metric series existed;
- X-Ray received Backend traces;
- Terraformers services appeared in the service graph;
- the Java instrumentation and CloudWatch export path worked on a real analysis request.

## 5. Incident-resolution evidence

### Application Signals pipeline restoration

Observed failure:

- CloudWatch add-on was Active but Application Signals metrics/traces and Java injection were absent.

Root causes resolved across PR #84 through PR #86:

1. custom CloudWatch agent configuration omitted Application Signals metric and trace receivers;
2. `monitorAllServices=false` had no Backend custom selector;
3. actual Micrometer CloudWatch metric names used emitted suffixes such as `.count` and `.avg`;
4. Pod-level `runAsNonRoot=true` had no Pod-level `runAsUser`, so the operator skipped injection for the init container.

Bounded final fix:

- restore Application Signals receivers;
- select only `terraformers-runtime/terraformers-backend`;
- keep `monitorAllServices=false`;
- align dashboard/alarm queries with emitted metric names;
- set Pod-level `runAsUser: 10001` without changing the image, network, node group, public exposure, or Terraform architecture.

### Runtime proof

The new Pod contained the expected init container, completed injection, remained Ready with zero restarts, returned health `UP`, and emitted Application Signals/X-Ray data from a real analysis request.

## 6. Claims supported by this evidence

Supported:

- immutable ECR digest delivery;
- Argo CD Synced/Healthy at the captured revision;
- non-root Backend Pod with successful Java auto-instrumentation;
- real analysis success;
- custom Backend and AOSS metric emission;
- Application Signals latency data;
- X-Ray traces and service graph presence;
- CloudWatch-native operations visibility.

Not supported or deliberately excluded:

- application high availability;
- HPA/autoscaling completion;
- multi-region disaster recovery;
- automatic deployment of generated Terraform;
- statistical RAG quality claims beyond the bounded v1/v2 comparison;
- current Argo CD revision after documentation-only commits until the final read-only parity check is captured.

## 7. Final pre-teardown refresh required

Immediately before runtime teardown, refresh only:

- current integration commit;
- current Argo CD revision, sync, and health;
- Deployment image and Pod image ID;
- Pod readiness and restart count;
- confirmation that the immutable digest remains unchanged;
- whether the last valid browser analysis result is retained as final evidence.

Do not repeat the full browser, RAG, or observability investigation unless the current read-only state contradicts this evidence.