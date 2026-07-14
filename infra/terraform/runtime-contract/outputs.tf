output "backend_runtime_config_keys" {
  description = "Non-secret backend runtime config key names. Values can be rendered into a ConfigMap by deployment tooling."
  value       = keys(local.backend_runtime_config)
}

output "backend_runtime_secret_keys" {
  description = "Secret runtime key names expected by the backend. Values must be stored in a secret manager, not printed in logs."
  value       = keys(local.backend_runtime_secret_values)
}

output "backend_runtime_config" {
  description = "Non-secret backend runtime config values."
  value       = local.backend_runtime_config
}

output "backend_runtime_secret_values" {
  description = "Sensitive backend runtime values. Use only for secret manager wiring."
  value       = local.backend_runtime_secret_values
  sensitive   = true
}
