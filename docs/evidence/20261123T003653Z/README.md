# Evidencia EP3 — 2026-11-23T01:54:12Z

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
| falla-controlada.txt | Falla controlada: alarma en ALARM y recuperación a OK (si se ejecutó `sesion_ep3.sh`) |
| deploy.txt | Despliegue medido con `deploy.sh` (si se ejecutó `sesion_ep3.sh`) |
| ie6-gate-seguridad.txt | PR bloqueado por Snyk (si se ejecutó `demo_gate_seguridad.sh`) |

## Notas de esta sesión

- `ie6-gate-bloqueante.txt` (PR Flask-Dashboard-S3#28) e `ie6-gate-seguridad.txt`
  (PR Flask-Dashboard-S3#27): estado de los checks y del merge con los PRs de
  demo abiertos; ambos se cerraron sin mergear.
- La alarma `citibike-dev-ci-gate-failed` pasó a `ALARM` por el PR de demo #28
  (`QualityGatePassed=0`) y volvió a `OK` al salir de su ventana de 1 hora;
  `cloudwatch-alarms.txt` se recolectó después, con las 8 alarmas en `OK`.
- `DeploymentDurationSeconds` tiene dos valores: 142 s de `deploy.sh` y 138 s
  del job `Deploy en AWS ECS` de Flask-Dashboard-S3 (run 45078823748, intento 2).
- `compliance.txt` se generó con un token sin permisos de administración: la
  protección de rama y `security_and_analysis` quedaron como no evaluables
  (29 controles, 0 fallas, 6 no evaluables). La auditoría completa
  (47 controles, 0 fallas) está en `../20261119T183438Z/compliance.txt`.
- La suscripción SNS de `alarm_email` no se confirmó: no hay correo de la alarma.
