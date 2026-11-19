# Evidencia EP3 — 2026-11-18T14:21:57Z

Generada con `./scripts/collect_evidence.sh`.

| Archivo | Contenido |
|---|---|
| verify.txt | Verificación end-to-end (`scripts/verify.sh`) |
| terraform-outputs.txt | URLs y nombres de recursos desplegados |
| ecs-services.txt | Servicios ECS con tareas deseadas/corriendo y rollout |
| ecs-instances.txt | Instancias registradas en el cluster |
| target-group-dashboard.txt / target-group-grafana.txt | Salud de los targets del ALB |
| http-status.txt | Códigos HTTP de `/health`, `/`, `/metrics` y Grafana |
| prometheus-up.txt | Series `up` (disponibilidad por job) |
| prometheus-rules.txt | Reglas de alerta cargadas y su estado |
| prometheus-alerts.txt | Alertas activas en el momento de la captura |
| cloudwatch-alarms.txt | Alarmas de CloudWatch y su estado |
| cloudwatch-metrics.txt | Métricas disponibles por namespace |
| cloudwatch-cicd-values.txt | Últimos valores de las métricas de CI/CD |
| compliance.txt / compliance.md | Auditoría de cumplimiento de los 3 repos |
