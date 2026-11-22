# CitiBike-Infra

Infraestructura como código y stack de observabilidad para el pipeline **DataOps Citi Bike** de la asignatura **DOY0101 (EP3)**.

Este repositorio despliega el dashboard y el stack de monitoreo en **Amazon ECS on EC2**, dentro de una cuenta **AWS Learner Lab**, sin crear roles IAM y con un costo controlado por sesión.

## Repositorios del pipeline

| Repositorio | Rol |
|---|---|
| [Extract-Bigquery-Dataset](https://github.com/Sebithaz-dev/Extract-Bigquery-Dataset) | Extracción BigQuery → S3 y ETL en Glue |
| [Model-Training-S3](https://github.com/Sebithaz-dev/Model-Training-S3) | Entrenamiento, quality gate y artefactos del modelo en S3 |
| [Flask-Dashboard-S3](https://github.com/Sebithaz-dev/Flask-Dashboard-S3) | Dashboard web, `/metrics`, `/health` y API de predicción |
| **CitiBike-Infra** (este repo) | ECS, ALB, Prometheus, Grafana, Alertmanager, blackbox y métricas CI/CD |

## Arquitectura

```
GitHub Actions ──► GHCR (app + imágenes de monitoreo) ──┐
        │                                                │
        │ CloudWatch: CitiBike/CI, CitiBike/Model        │
        ▼                                                ▼
┌──────────────────────────────────────────────────────────────────┐
│ AWS Learner Lab · us-east-1 · VPC default                        │
│                                                                  │
│  ALB :80 ──────────────► ECS on EC2 (t3.large, AL2023)           │
│  ALB :3000 ────────────►  ├─ dashboard (Flask, :5000, /metrics)  │
│                           ├─ prometheus (:9090, solo host)       │
│                           ├─ grafana (:3000)                     │
│                           ├─ alertmanager (:9093, solo host)     │
│                           └─ blackbox-exporter (:9115, host)     │
│                                                                  │
│  CloudWatch Logs ◄── awslogs (todos los contenedores)            │
│  CloudWatch Metrics ◄── Container Insights + scripts CI          │
└──────────────────────────────────────────────────────────────────┘
```

- **Sin IAM nuevo:** se reutilizan `LabInstanceProfile` (EC2) y `LabRole` (task role/execution role). El Learner Lab deniega `iam:CreateRole` e `iam:AttachRolePolicy`.
- **Sin IRSA ni Cloud Map:** ECS on EC2 con `network_mode=host` para el stack de monitoreo.
- **Sin contenedores privilegiados:** no se monta el Docker socket; las métricas de host vienen de CloudWatch Container Insights.

### ¿Por qué ECS y no Kubernetes?

La EP2 usó Kubernetes simulado (`kind`) y manifiestos en `Flask-Dashboard-S3/k8s/`. Para la EP3 se evaluó EKS real y se optó por ECS on EC2 por costo y simplicidad de operación, **con autorización del docente del curso**:

| Criterio | EKS | **ECS on EC2 (elegido)** |
|---|---|---|
| Crear roles IAM | Requiere roles adicionales para addons/IRSA | Usa `LabRole`/`LabInstanceProfile` existentes |
| Descubrimiento de servicios | Cloud Map o CoreDNS | Puertos fijos en una instancia |
| Costo por sesión de 4 h | ~USD 0.75 (control plane + nodo) | ~USD 0.46 |
| Operación | Addons, nodegroups, kubectl/helm | Terraform + AWS CLI |
| Cumple "entorno orquestado en la nube" | Sí | Sí |

La desviación se documenta en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) con el detalle de las verificaciones realizadas.

## Componentes

| Servicio ECS | Imagen | Puerto | Función |
|---|---|---|---|
| `dashboard` | `ghcr.io/sebithaz-dev/flask-dashboard-s3` | 5000 (ALB :80) | Dashboard Flask con `/metrics`, `/health`, logs JSON y `X-Request-ID` |
| `prometheus` | `ghcr.io/sebithaz-dev/citibike-prometheus` | 9090 | Scraping de `/metrics` + probes de disponibilidad |
| `grafana` | `ghcr.io/sebithaz-dev/citibike-grafana` | 3000 (ALB :3000) | Dashboard unificado Prometheus + CloudWatch |
| `alertmanager` | `ghcr.io/sebithaz-dev/citibike-alertmanager` | 9093 | Enrutamiento de alertas de Prometheus |
| `blackbox` | `ghcr.io/sebithaz-dev/citibike-blackbox` | 9115 | Disponibilidad de ECS, Grafana y Render |

### Dashboard de Grafana (IE3)

El dashboard `CitiBike EP3 - Observabilidad unificada` se aprovisiona automáticamente y tiene cinco filas:

1. **Disponibilidad:** `up{job="dashboard"}`, `probe_success` de ECS/Grafana/Render, estado del quality gate y tareas ECS corriendo.
2. **Errores y latencia:** requests/s, 5xx/s, errores no controlados y latencia p95.
3. **Recursos:** CPU/memoria del servicio y CPU del cluster (CloudWatch Container Insights).
4. **CI/CD y modelo:** duración del despliegue (publicada por el job `deploy-ecs` de Flask-Dashboard-S3), cobertura de tests por repo (Flask y Model-Training) y ROC-AUC histórico del modelo.
5. **Logs:** errores registrados en los logs (nivel `ERROR` o status 5xx, cada 5 min) y los logs recientes del dashboard, consultados en CloudWatch Logs desde Grafana.

## Costos

Tarifas aproximadas en `us-east-1` (Learner Lab incluye créditos, pero el límite es USD 50):

| Recurso | USD/hora | USD por sesión de 4 h |
|---|---|---|
| `t3.large` | 0.0832 | 0.33 |
| EBS gp3 30 GB | 0.0024 | 0.01 |
| ALB | 0.0225 | 0.09 |
| CloudWatch (logs + métricas) | ~0.01 | ~0.04 |
| **Total** | **~0.12** | **~0.46** |

No hay NAT Gateway, EKS, RDS ni EIP. **Destruir con `./scripts/down.sh` al final de cada sesión.**

## Requisitos

- Terraform >= 1.5
- AWS CLI v2
- `jq` (opcional)
- Credenciales temporales del Learner Lab en el entorno:
  ```bash
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  export AWS_SESSION_TOKEN=...
  export AWS_REGION=us-east-1
  ```
- Imágenes publicadas en GHCR (el workflow `Monitoring Images` las construye en `main`; las de la app las publican sus propios repos).

## Puesta en marcha

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edita s3_bucket_name e image_tag si hace falta

./scripts/up.sh          # terraform init + apply y muestra las URLs
./scripts/deploy.sh "$(git rev-parse --short HEAD)"   # despliegue medido
./scripts/down.sh        # destruye todo al terminar

# Sesión EP3 completa (up + verify + tráfico + deploy + falla controlada + evidencia)
./scripts/sesion_ep3.sh
./scripts/demo_gate_seguridad.sh ../Flask-Dashboard-S3 docs/evidence/<fecha>   # IE6 seguridad
```

Grafana queda en `http://<alb-dns>:3000` con usuario `admin`. La contraseña la genera Terraform en cada entorno (no está en el repositorio):

```bash
terraform -chdir=terraform output -raw grafana_admin_password
```

Para recibir las alarmas por correo, define `alarm_email` en `terraform/terraform.tfvars` y confirma la suscripción SNS que llega por correo. El acceso anónimo está habilitado como **Viewer** para facilitar la evaluación; en producción se deshabilitaría y se usaría TLS.

## Despliegue automático en ECS

Cada push a `main` de Flask-Dashboard-S3 que pasa tests, smoke test, kind y publicación en GHCR ejecuta el job **`deploy-ecs`**: registra una revisión nueva de la task definition con la imagen `:<sha>`, actualiza el servicio `dashboard`, espera a que quede estable, confirma que no hubo rollback del circuit breaker y publica la duración en CloudWatch. Si el Learner Lab está apagado, el job lo informa con un warning y no falla.

> `terraform apply` (`up.sh` / `deploy.sh`) vuelve a fijar la imagen de `var.image_tag`. Después de recrear el entorno, el siguiente push a `main` vuelve a desplegar la imagen del commit.

## Observabilidad y alertas

- **Prometheus** scrapea el dashboard, blackbox y a sí mismo cada 15 s.
- **Blackbox** mide disponibilidad de `http://localhost:5000/health`, `http://localhost:3000/api/health` y `https://flask-dashboard-s3.onrender.com/health`.
- **Alertas** (`docker/prometheus/alerts.yml`): `DashboardDown`, `PublicEndpointDown`, `GrafanaDown`, `HighErrorRate` (>5 % de 5xx), `HighLatencyP95` (>1 s) y `UnhandledErrors`.
- **CloudWatch Logs** recibe todos los contenedores vía `awslogs` con retención de 7 días. Los logs del dashboard son JSON con `request_id`.
- **Métricas CI/CD** en `CitiBike/CI`: `TestCoveragePercent`, `TestsPassed/Failed` (dimensión `Repo`) y `QualityGatePassed` (1 si los tests pasan, 0 si fallan) desde el CI de cada repo; `DeploymentDurationSeconds` y `DeploymentSucceeded` desde el job `deploy-ecs` del pipeline de Flask (o `scripts/deploy.sh` en un despliegue manual).
- **Alarmas de CloudWatch** (`terraform/monitoring.tf`): 8 alarmas (disponibilidad, 5xx, latencia p95, CPU, memoria, gate de CI, gate del modelo y despliegue fallido). Con `alarm_email` notifican por SNS al entrar en `ALARM` y al volver a `OK`.
- **Métricas del modelo** (`Model-Training-S3/ml/metrics_export.py`): `roc_auc`, `f1_score`, `QualityGatePassed`, etc. en `CitiBike/Model`.
- **Guía de verificación manual** (dashboard, logs, alarmas, falla controlada, gates y cierre): [`docs/TESTING.md`](docs/TESTING.md).

## CI del repositorio

| Workflow | Qué hace |
|---|---|
| `infra-ci.yml` | `terraform fmt -check`, `init -backend=false`, `validate`, `promtool check config/rules`, `amtool check-config` y validación del JSON del dashboard |
| `monitoring-images.yml` | Construye y publica las cuatro imágenes de monitoreo en GHCR (multi-stage por matriz) |

## Postura de seguridad

- IAM: **no se crean roles ni políticas**; se usan los del laboratorio.
- Instancia con **IMDSv2 obligatorio** (`http_tokens = required`) y EBS cifrado.
- Contenedores sin `privileged`, sin montar el socket de Docker y con límites de CPU/memoria.
- Puertos de Prometheus/Alertmanager/blackbox **no expuestos** por el ALB ni por el security group.
- Logs con retención explícita; S3 con cifrado y lectura pública solo para `GetObject`.
- Branch protection, secret scanning, Dependabot y quality gates en los repos de aplicación.

## Estado de la EP3

Última verificación end-to-end: **2026-11-18**, `./scripts/verify.sh --wait` →
`Todo OK` (evidencia en [`docs/evidence/`](docs/evidence/)).

| IE | Evidencia en este repo | Estado |
|---|---|---|
| IE1 (20 %) | Prometheus + Grafana + CloudWatch Logs, 6 reglas de alerta, 8 alarmas de CloudWatch (disponibilidad, 5xx, latencia p95, CPU, memoria, quality gates, despliegue) con notificación SNS y logs visibles en Grafana | ✅ desplegado y verificado |
| IE2 (20 %) | Terraform ECS/ALB en AWS real: 5/5 servicios `1/1`, target groups `healthy`, `/health` `/` `/metrics` 200; despliegue automático desde el pipeline (`deploy-ecs`) | ✅ desplegado y verificado |
| IE3 (10 %) | Dashboard de 5 filas (disponibilidad, errores/latencia, recursos, CI/CD, logs); cobertura publicada por el CI de ambos repos y duración del despliegue por el job `deploy-ecs` | ✅ con datos reales (cobertura 83,61 %, 29 tests) |
| IE4 (10 %) | `README`, `docs/ARCHITECTURE.md`, `docs/RUNBOOK.md`, `docs/COMPLIANCE.md` | 🟡 falta el informe EP3 y las reflexiones individuales |
| IE5 (20 %) | Branch protection, checks requeridos, CODEOWNERS, Dependabot, secret scanning y `scripts/audit_compliance.py` (46/46 controles) | ✅ auditado |
| IE6 (20 %) | Quality gate del modelo, cobertura mínima, Snyk/Sonar, `terraform validate`, circuit breaker y alarmas | ✅ implementado; falta la captura de un PR bloqueado |

## Próximos pasos

1. Redactar el informe EP3 (matriz IE → evidencia, capturas de Grafana y CloudWatch,
   declaración de uso de IA) y las reflexiones individuales.
2. Capturar un PR que se detenga solo (evidencia de IE6) y adjuntarlo.
3. Repetir `./scripts/collect_evidence.sh` al inicio de cada sesión para dejar la
   evidencia con la fecha del día.
