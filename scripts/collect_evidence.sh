#!/usr/bin/env bash
# Recolecta la evidencia de la EP3 en docs/evidence/<fecha-hora>/.
#
# Junta en un solo lugar lo que el informe necesita: verificacion end-to-end,
# estado de ECS y del ALB, targets de Prometheus, alarmas y metricas de
# CloudWatch y la auditoria de cumplimiento.
#
# Uso:
#   ./scripts/collect_evidence.sh            # requiere credenciales AWS y gh
#   OUT_DIR=docs/evidence/manual ./scripts/collect_evidence.sh
set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${ECS_CLUSTER:-citibike-dev-cluster}"
OUT_DIR="${OUT_DIR:-docs/evidence/$(date -u +%Y%m%dT%H%M%SZ)}"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: credenciales AWS invalidas o expiradas." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

ALB="$(terraform -chdir=terraform output -raw alb_dns_name)"
DASHBOARD_URL="http://${ALB}"
GRAFANA_URL="http://${ALB}:3000"
# La contrasena de Grafana la genera Terraform (random_password); no hay una fija.
GRAFANA_PASS="${GRAFANA_PASS:-$(terraform -chdir=terraform output -raw grafana_admin_password 2>/dev/null || true)}"

echo "== Recolectando evidencia en ${OUT_DIR} =="

echo "-- verificacion end-to-end"
./scripts/verify.sh --wait >"${OUT_DIR}/verify.txt" 2>&1 || true

echo "-- entorno (outputs de terraform)"
terraform -chdir=terraform output >"${OUT_DIR}/terraform-outputs.txt" 2>&1 || true

echo "-- servicios ECS"
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services dashboard grafana prometheus alertmanager blackbox \
  --query 'services[].{servicio:serviceName,estado:status,deseadas:desiredCount,corriendo:runningCount,rollout:deployments[0].rolloutState,tarea:taskDefinition}' \
  --output table >"${OUT_DIR}/ecs-services.txt" 2>&1

echo "-- container instances"
aws ecs list-container-instances --cluster "$CLUSTER" \
  --query 'containerInstanceArns' --output text >"${OUT_DIR}/ecs-instances.txt" 2>&1

echo "-- target groups"
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups --names citibike-dev-dash --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].{target:Target.Id,puerto:Target.Port,estado:TargetHealth.State}' \
  --output table >"${OUT_DIR}/target-group-dashboard.txt" 2>&1
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups --names citibike-dev-graf --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].{target:Target.Id,puerto:Target.Port,estado:TargetHealth.State}' \
  --output table >"${OUT_DIR}/target-group-grafana.txt" 2>&1

echo "-- disponibilidad HTTP"
{
  for path in /health / /metrics; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${DASHBOARD_URL}${path}")"
    printf '%-10s %s\n' "$path" "$code"
  done
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${GRAFANA_URL}/api/health")"
  printf '%-10s %s\n' "grafana" "$code"
} >"${OUT_DIR}/http-status.txt" 2>&1

echo "-- targets y reglas de Prometheus"
GRAFANA_URL="$GRAFANA_URL" GRAFANA_PASS="$GRAFANA_PASS" python3 - "$OUT_DIR" <<'PY'
import base64
import json
import os
import sys
import urllib.request

out_dir = sys.argv[1]
base = os.environ["GRAFANA_URL"] + "/api/datasources/proxy/uid/prometheus/api/v1/"
auth = base64.b64encode(("admin:" + os.environ["GRAFANA_PASS"]).encode()).decode()


def get(path):
    request = urllib.request.Request(base + path)
    request.add_header("Authorization", "Basic " + auth)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


up = get("query?query=up")["data"]["result"]
with open(os.path.join(out_dir, "prometheus-up.txt"), "w") as handle:
    handle.write(f"{'job':12} {'instance':50} up\n")
    for row in sorted(up, key=lambda r: (r["metric"].get("job", ""), r["metric"].get("instance", ""))):
        handle.write(
            "{job:12} {inst:50} {val}\n".format(
                job=row["metric"].get("job", "?"),
                inst=row["metric"].get("instance", "?"),
                val=row["value"][1],
            )
        )

rules = get("rules")["data"]["groups"]
with open(os.path.join(out_dir, "prometheus-rules.txt"), "w") as handle:
    for group in rules:
        handle.write(f"[{group['name']}]\n")
        for rule in group["rules"]:
            handle.write(f"  {rule['name']:22} {rule.get('state', 'inactive'):9} {rule.get('query', '')}\n")

alerts = get("alerts")["data"]["alerts"]
with open(os.path.join(out_dir, "prometheus-alerts.txt"), "w") as handle:
    handle.write(f"alertas activas: {len(alerts)}\n")
    for alert in alerts:
        handle.write(f"  {alert['labels'].get('alertname')} {alert['state']}\n")
PY

echo "-- alarmas de CloudWatch"
aws cloudwatch describe-alarms \
  --alarm-name-prefix citibike-dev \
  --query 'MetricAlarms[].{alarma:AlarmName,estado:StateValue,metrica:MetricName,umbral:Threshold}' \
  --output table >"${OUT_DIR}/cloudwatch-alarms.txt" 2>&1

echo "-- metricas de CloudWatch con datos"
{
  for ns in CitiBike/Model CitiBike/CI ECS/ContainerInsights CWAgent; do
    echo "## ${ns}"
    aws cloudwatch list-metrics --namespace "$ns" --query 'Metrics[].MetricName' --output text 2>/dev/null | tr '\t' '\n' | sort -u
    echo
  done
} >"${OUT_DIR}/cloudwatch-metrics.txt" 2>&1

echo "-- ultimas metricas de CI/CD y modelo"
{
  end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start="$(date -u -d '-6 hours' +%Y-%m-%dT%H:%M:%SZ)"
  # Cobertura y tests se publican por repo (dimension Repo).
  for repo in Flask-Dashboard-S3 Model-Training-S3; do
    for metric in TestCoveragePercent TestsPassed TestsFailed; do
      echo "## CitiBike/CI ${metric} (Repo=${repo})"
      aws cloudwatch get-metric-statistics --namespace CitiBike/CI \
        --metric-name "$metric" --dimensions "Name=Repo,Value=${repo}" \
        --start-time "$start" --end-time "$end" \
        --period 300 --statistics Maximum \
        --query 'Datapoints[].{fecha:Timestamp,valor:Maximum}' --output table 2>/dev/null
    done
  done
  # Gate y despliegue van sin dimensiones (las alarmas los agregan).
  for metric in QualityGatePassed DeploymentDurationSeconds DeploymentSucceeded; do
    echo "## CitiBike/CI ${metric}"
    aws cloudwatch get-metric-statistics --namespace CitiBike/CI \
      --metric-name "$metric" --start-time "$start" --end-time "$end" \
      --period 300 --statistics Minimum Maximum \
      --query 'Datapoints[].{fecha:Timestamp,min:Minimum,max:Maximum}' --output table 2>/dev/null
  done
  for metric in QualityGatePassed roc_auc f1_score; do
    echo "## CitiBike/Model ${metric}"
    aws cloudwatch get-metric-statistics --namespace CitiBike/Model \
      --metric-name "$metric" --start-time "$(date -u -d '-7 days' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$end" \
      --period 3600 --statistics Maximum \
      --query 'Datapoints[].{fecha:Timestamp,valor:Maximum}' --output table 2>/dev/null
  done
} >"${OUT_DIR}/cloudwatch-cicd-values.txt" 2>&1

echo "-- auditoria de cumplimiento"
python3 scripts/audit_compliance.py --markdown >"${OUT_DIR}/compliance.md" 2>&1 || true
python3 scripts/audit_compliance.py >"${OUT_DIR}/compliance.txt" 2>&1 || true

cat >"${OUT_DIR}/README.md" <<EOF
# Evidencia EP3 — $(date -u +%Y-%m-%dT%H:%M:%SZ)

Generada con \`./scripts/collect_evidence.sh\`.

| Archivo | Contenido |
|---|---|
| verify.txt | Verificación end-to-end (\`scripts/verify.sh\`) |
| terraform-outputs.txt | URLs y nombres de recursos desplegados |
| ecs-services.txt | Servicios ECS con tareas deseadas/corriendo y rollout |
| ecs-instances.txt | Instancias registradas en el cluster |
| target-group-dashboard.txt / target-group-grafana.txt | Salud de los targets del ALB |
| http-status.txt | Códigos HTTP de \`/health\`, \`/\`, \`/metrics\` y Grafana |
| prometheus-up.txt | Series \`up\` (disponibilidad por job) |
| prometheus-rules.txt | Reglas de alerta cargadas y su estado |
| prometheus-alerts.txt | Alertas activas en el momento de la captura |
| cloudwatch-alarms.txt | Alarmas de CloudWatch y su estado |
| cloudwatch-metrics.txt | Métricas disponibles por namespace |
| cloudwatch-cicd-values.txt | Últimos valores de las métricas de CI/CD |
| compliance.txt / compliance.md | Auditoría de cumplimiento de los 3 repos |
| falla-controlada.txt | Falla controlada: alarma en ALARM y recuperación a OK (si se ejecutó \`sesion_ep3.sh\`) |
| deploy.txt | Despliegue medido con \`deploy.sh\` (si se ejecutó \`sesion_ep3.sh\`) |
| ie6-gate-seguridad.txt | PR bloqueado por Snyk (si se ejecutó \`demo_gate_seguridad.sh\`) |
EOF

echo "Listo: ${OUT_DIR}"
