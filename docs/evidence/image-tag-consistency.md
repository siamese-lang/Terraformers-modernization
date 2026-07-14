# Image Tag Consistency Evidence Template

## Scope

Backend and analysis service image tag consistency after ECR publish and manifest update.

## Checks

```bash
kubectl get deploy backend-app -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
kubectl get deploy bedrock-service -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
```

Compare runtime image values with the Git manifest image values.

## Expected result

- Runtime backend image equals the image URI committed by the publish workflow.
- Runtime bedrock image equals the image URI committed by the publish workflow.
- Old DockerHub image placeholders are not left in runtime manifests.

## Current state

Kubernetes manifests and image publish workflows will be imported after backend baseline validation.
