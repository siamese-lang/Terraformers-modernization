# Operations visibility

## Telemetry design

The Terraform-managed `amazon-cloudwatch-observability` EKS add-on provides enhanced Container Insights, container application logs, and the AWS-native OpenTelemetry/X-Ray-compatible trace path. Its dedicated `amazon-cloudwatch/cloudwatch-agent` IRSA role has `CloudWatchAgentServerPolicy` and `AWSXrayWriteOnlyAccess`; neither policy is attached to a worker node. The Backend's existing IRSA role has only `cloudwatch:PutMetricData` constrained to `Terraformers/Backend` for direct Micrometer CloudWatch2 publication.

The AWS/GitOps Backend pod template alone has the supported Java auto-instrumentation annotation. `/actuator/prometheus` is exposed by Spring only on the existing pod port; the Service, internal ALB Ingress, and CloudFront route remain limited to `/api`, so it is not public.

## Metrics and bounded dimensions

CloudWatch namespace: `Terraformers/Backend`.

| Metric | Meaning | Allowed dimensions |
| --- | --- | --- |
| `terraformers.analysis.jobs` | started, succeeded, failed jobs | `outcome`; failed only adds bounded `exception_category` |
| `terraformers.analysis.duration` | end-to-end job latency | service/environment defaults only |
| `terraformers.bedrock.invocation` | Bedrock call latency and failure state | `outcome`, bounded `exception_category` |
| `terraformers.aoss.retrieval` | AOSS retrieval latency and failure state | `outcome`, bounded `exception_category` |
| `terraformers.aoss.retrieved_hits` | retrieved document count | service/environment defaults only |
| `terraformers.analysis.executor.queue.depth` / `.rejections` | actual analysis executor queue pressure and rejected tasks | service/environment defaults only |

Spring/Micrometer supplies Hikari pool and HTTP metrics; Application Signals supplies request latency and fault state. The CloudWatch2 registry filters direct publication to the `terraformers.` metrics listed here, while Prometheus retains the internal framework metrics. Metric labels never include user/project/job IDs, prompts, files, documents, Terraform output, trace IDs, exception messages, or credentials.

## Logs and tracing

When an analysis job runs, its executor thread restores `analysisJobId` in MDC. The console format also includes OpenTelemetry `trace_id` and `span_id` when present plus `source_revision` from the image build argument. Logs deliberately omit Cognito subjects/tokens, project IDs, source/retrieved/generated content, endpoint credentials, and raw exception messages.

## Dashboard, alarms, and operations

One Terraform dashboard covers node/pod CPU and memory, restarts, Backend latency/faults, analysis outcomes/duration, Bedrock/AOSS telemetry, and the environment/service identity. The three alarms are Backend Application Signals faults, failed analysis jobs, and repeated Container Insights restarts.

**Live apply order:** review Terraform plan for EKS runtime; apply manually after approval; wait for the add-on Pods and their resource requests to schedule (the current two workers are retained because one worker exhausted Pod capacity); reconcile the GitOps manifest; publish a new immutable Backend image so `BUILD_SOURCE_REVISION` is present.

**Acceptance:** confirm the add-on is Active, agent Pods are Ready, CloudWatch logs/Container Insights and X-Ray trace arrive, dashboard widgets populate, and one bounded analysis correlates by `analysisJobId`, trace/span IDs, and source revision. Confirm `/actuator/prometheus` from an internal pod only and that CloudFront still cannot route it.

**Rollback/cost:** revert the Terraform resources and GitOps annotation/config only after checking trace/log retention. Costs increase for CloudWatch Container Insights metrics/log ingestion and retention, Application Signals, dashboard/alarm evaluations, X-Ray trace ingestion/storage, and the add-on's DaemonSet/deployment CPU and memory requests. No public monitoring endpoint or second dashboard stack is introduced.
