# Arquitectura y decisiones — CitiBike-Infra (EP3)

## Contexto

El pipeline Citi Bike tiene tres etapas ya implementadas en repos separados:

1. **Extracción** (`Extract-Bigquery-Dataset`): BigQuery → Parquet → S3.
2. **Entrenamiento** (`Model-Training-S3`): valida datos, entrena, mide y publica artefactos en S3.
3. **Dashboard** (`Flask-Dashboard-S3`): consume Parquet y el modelo desde S3; expone `/metrics` y `/health`.

La EP3 exige observabilidad, despliegue en un entorno orquestado en la nube, dashboards, compliance y gates bloqueantes. Este repositorio cubre la infraestructura y el monitoreo de las tres etapas.

## Restricciones del entorno

Verificadas con AWS CLI antes de escribir el Terraform:

| Restricción | Evidencia |
|---|---|
| No se pueden crear roles ni adjuntar políticas | `iam:CreateRole` y `iam:AttachRolePolicy` → `implicitDeny` |
| Roles precreados disponibles | `LabRole` (confía en `ecs-tasks.amazonaws.com`, `logs.amazonaws.com`, `ec2.amazonaws.com`), `LabInstanceProfile` |
| Permisos ECS/ALB/EventBridge/CloudWatch | `ecs:CreateService`, `elasticloadbalancing:CreateLoadBalancer`, `cloudwatch:PutDashboard`, `logs:CreateLogGroup` → `allowed` |
| Red | VPC default con 6 subredes públicas; no hay NAT |
| Costo | Límite USD 50, sesiones de 4 h con credenciales rotativas |
| Imágenes | GHCR público; no hace falta ECR |

## Decisión 1 — ECS on EC2 en lugar de EKS

**Estado:** aceptada, con autorización del docente del curso (por costo).

**Contexto:** la EP2 desplegó Kubernetes simulado con `kind` y dejó manifiestos en `Flask-Dashboard-S3/k8s/`. La opción "más directa" para IE2 sería EKS real.

**Alternativas:**

- **EKS con roles precreados:** viable, pero requiere addons (VPC CNI, CoreDNS, kube-proxy), nodegroups, `kubectl`/`helm` y Cloud Map o un Service para descubrimiento. Además el agente de CloudWatch necesita IRSA o un rol adjunto, ambos bloqueados.
- **ECS Fargate:** evita administrar la instancia, pero obliga a ALB/Cloud Map para descubrir tareas, no ofrece métricas de host y el stack de monitoreo cuesta más.
- **ECS on EC2 (elegida):** una instancia ECS-optimized con `LabInstanceProfile`, puertos fijos, `LabRole` como task/execution role y métricas de host vía Container Insights.

**Consecuencias:**

- Se cumple "entorno orquestado en la nube" con ECS, sin crear IAM.
- Se pierde la portabilidad de Kubernetes; los manifiestos de la EP2 quedan como evidencia histórica.
- El stack de monitoreo usa `network_mode=host` (puertos 9090/9093/9115 no expuestos).
- La instancia es un único punto de falla; aceptable para una demo académica y documentado en el runbook.

## Decisión 2 — Observabilidad con Prometheus + Grafana + CloudWatch

**Estado:** aceptada.

- **Prometheus** cubre métricas de aplicación (`/metrics` de Flask), latencia, errores y disponibilidad vía blackbox.
- **CloudWatch** cubre logs (`awslogs`), CPU/memoria de ECS (Container Insights) y métricas del pipeline (`CitiBike/CI`, `CitiBike/Model`).
- **Grafana** unifica ambos datasources en un solo dashboard de cinco filas (la quinta muestra los logs de CloudWatch Logs).
- **Alertmanager** recibe las reglas de Prometheus; no envía correo, las alertas se visualizan en Prometheus/Grafana; las notificaciones por correo salen de las alarmas de CloudWatch vía SNS (`alarm_email`).
- **Se descartó Loki/Promtail** porque requiere montar el Docker socket (contenedor privilegiado) o un agente con permisos adicionales.

## Decisión 3 — Imágenes de monitoreo horneadas

**Estado:** aceptada.

Las configuraciones (`prometheus.yml`, reglas, provisioning de Grafana, dashboards) se copian dentro de imágenes publicadas en GHCR. Ventajas:

- El task definition no necesita volúmenes ni descarga de configuración al arrancar.
- La configuración queda versionada y auditable en Git.
- El despliegue es reproducible: `image_tag` = SHA del commit.

La URL de Render se inyecta por variable de entorno y un `entrypoint.sh` la sustituye en el arranque, sin reconstruir la imagen.

## Decisión 4 — Sin secretos estáticos para Grafana

Grafana usa el **task role** (`LabRole`) a través del endpoint de credenciales de contenedor de ECS. No hay claves AWS dentro de la imagen ni en variables de entorno. Es la única forma compatible con la restricción de no crear IAM, y elimina el riesgo de filtrar credenciales en el repositorio.

## Flujo de despliegue

```
terraform apply
   ├─ SG + ALB + listeners (:80 dashboard, :3000 grafana)
   ├─ instancia ECS-optimized (user_data registra el cluster)
   ├─ log groups (retención 7 días)
   ├─ task definitions (dashboard, prometheus, grafana, alertmanager, blackbox)
   └─ ECS services (desired_count=1, circuit breaker con rollback)

./scripts/deploy.sh <sha>
   ├─ terraform apply -var image_tag=<sha>
   ├─ aws ecs update-service --force-new-deployment
   ├─ aws ecs wait services-stable
   └─ publica DeploymentDurationSeconds en CloudWatch/CitiBike/CI
```

## Mapeo a los indicadores de evaluación

| IE | Cómo se evidencia |
|---|---|
| IE1 | Prometheus + Grafana + CloudWatch Logs + alertas + probes de disponibilidad de ECS, Grafana y Render |
| IE2 | Terraform reproducible, ECS/ALB real, despliegue medido y trazable por SHA |
| IE3 | Dashboard de 5 filas con disponibilidad, errores, CPU/memoria, duración de despliegue, cobertura por repo, ROC-AUC y logs |
| IE4 | Este documento + README + runbook + informe EP3 |
| IE5 | IaC auditable, IAM mínimo, IMDSv2, EBS cifrado, branch protection y secret scanning en los repos |
| IE6 | Quality gate del modelo y alertas que bloquean/visibilizan regresiones |

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Credenciales del Learner Lab expiran cada 4 h | Preflight en `train.yml`; `up.sh` falla rápido con mensaje claro |
| Costo acumulado | `down.sh` obligatorio; sin NAT/EKS/RDS; retención de logs 7 días |
| Instancia única | Recreación con `terraform apply`; health checks y circuit breaker |
| Datos de Prometheus en disco efímero | Retención 6 h y foco en la sesión; dashboard histórico vive en CloudWatch |
| Dashboard público sin TLS | Documentado como excepción controlada de demo; en producción se agrega ACM + HTTPS |
| Puerto 3000 abierto | Solo Grafana; Prometheus/Alertmanager/blackbox quedan en el host sin exposición |
