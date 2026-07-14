# Backend Runtime Evidence Template

## Scope

Backend runtime health and required configuration key presence.

## Commands

```bash
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8080/internal/runtime/required-config
```

## Expected result

- `/actuator/health` returns healthy status.
- `/internal/runtime/required-config` returns key names and boolean presence only.
- Secret values are not returned.

## Kubernetes checks after deployment

```bash
kubectl rollout status deploy/backend-app -n default
kubectl get deploy,po,svc,endpoints -n default
kubectl logs deploy/backend-app -n default --tail=120
```

## Notes

`/internal/runtime/required-config` is an internal operational check surface. It should not be exposed publicly through ingress without access control.
