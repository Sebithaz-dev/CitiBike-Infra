#!/usr/bin/env bash
# Sesion completa de la EP3 en un solo comando: levanta el entorno, verifica,
# genera trafico, mide un despliegue, provoca una falla controlada (alarma en
# ALARM y vuelta a OK) y recolecta toda la evidencia en docs/evidence/<fecha>/.
#
# Al terminar deja el entorno ARRIBA para sacar las capturas de Grafana y de
# la consola de AWS. Despues hay que ejecutar ./scripts/down.sh.
#
# Uso:
#   ./scripts/sesion_ep3.sh
#
# Requisitos: credenciales del Learner Lab exportadas en el shell, terraform,
# aws CLI, gh autenticado (para la auditoria), curl y python3.
set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${ECS_CLUSTER:-citibike-dev-cluster}"
ALARM="citibike-dev-dashboard-unhealthy"
OUT_DIR="${OUT_DIR:-docs/evidence/$(date -u +%Y%m%dT%H%M%SZ)}"
export AWS_REGION="$REGION" OUT_DIR

paso() { printf '\n==== %s ====\n' "$*"; }

alarm_state() {
  aws cloudwatch describe-alarms --alarm-names "$ALARM" \
    --query 'MetricAlarms[0].StateValue' --output text
}

# Espera hasta que la alarma llegue al estado pedido (max. $2 segundos).
wait_alarm() {
  local target="$1" limit="$2" waited=0 state
  while [ "$waited" -lt "$limit" ]; do
    state="$(alarm_state)"
    printf '  %s  %s = %s\n' "$(date -u +%H:%M:%S)" "$ALARM" "$state"
    [ "$state" = "$target" ] && return 0
    sleep 20
    waited=$((waited + 20))
  done
  return 1
}

paso "0. Prerrequisitos"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: credenciales AWS invalidas o expiradas. Copia las del Learner Lab." >&2
  exit 1
fi
for cmd in terraform curl python3 gh; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: falta $cmd" >&2; exit 1; }
done
if [ ! -f terraform/terraform.tfvars ]; then
  cp terraform/terraform.tfvars.example terraform/terraform.tfvars
  echo "Se creo terraform/terraform.tfvars desde el example."
fi
if ! grep -qs '^alarm_email *= *"[^"]' terraform/terraform.tfvars && [ -z "${TF_VAR_alarm_email:-}" ]; then
  echo "AVISO: alarm_email no esta definido: la falla controlada no enviara correo."
  echo "       Para la captura del correo, define alarm_email en terraform/terraform.tfvars."
fi
mkdir -p "$OUT_DIR"

paso "1. Levantar el entorno (terraform apply)"
./scripts/up.sh

paso "2. Esperar servicios estables y verificar"
./scripts/verify.sh --wait

ALB="$(terraform -chdir=terraform output -raw alb_dns_name)"

paso "3. Generar trafico para las graficas (2 min aprox.)"
for _ in $(seq 1 60); do
  curl -s -o /dev/null --max-time 10 "http://${ALB}/" || true
  curl -s -o /dev/null --max-time 10 "http://${ALB}/health" || true
  curl -s -o /dev/null --max-time 10 "http://${ALB}/api/resumen" || true
  curl -s -o /dev/null --max-time 10 "http://${ALB}/exploracion" || true
  curl -s -o /dev/null --max-time 10 "http://${ALB}/api/modelo/metricas" || true
  sleep 1
done

paso "4. Despliegue medido (publica DeploymentDurationSeconds)"
./scripts/deploy.sh latest 2>&1 | tee "${OUT_DIR}/deploy.txt"

paso "5. Falla controlada: dashboard a 0 tareas"
{
  echo "# Falla controlada — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Estado inicial: $(alarm_state)"
  echo
  echo "## Dashboard detenido (desired-count 0)"
  aws ecs update-service --cluster "$CLUSTER" --service dashboard --desired-count 0 \
    --query 'service.desiredCount' --output text
  if wait_alarm ALARM 600; then
    echo "-> la alarma paso a ALARM"
  else
    echo "-> la alarma NO llego a ALARM en 10 minutos"
  fi
  echo
  echo "## Dashboard restaurado (desired-count 1)"
  aws ecs update-service --cluster "$CLUSTER" --service dashboard --desired-count 1 \
    --query 'service.desiredCount' --output text
  aws ecs wait services-stable --cluster "$CLUSTER" --services dashboard
  if wait_alarm OK 600; then
    echo "-> la alarma volvio a OK"
  else
    echo "-> la alarma NO volvio a OK en 10 minutos"
  fi
  echo
  echo "## Historial de la alarma"
  aws cloudwatch describe-alarm-history --alarm-name "$ALARM" \
    --history-item-type StateUpdate --max-records 6 \
    --query 'AlarmHistoryItems[].{fecha:Timestamp,cambio:HistorySummary}' --output table
} 2>&1 | tee "${OUT_DIR}/falla-controlada.txt"

paso "6. Recolectar evidencia"
./scripts/collect_evidence.sh

paso "Listo"
cat <<EOF
Evidencia en: ${OUT_DIR}

El entorno sigue ARRIBA. Saca ahora las capturas de
Model-Training-S3/docs/img/README.md:

  Grafana:  http://${ALB}:3000   (usuario admin)
  Password: terraform -chdir=terraform output -raw grafana_admin_password
  Consola AWS: CloudWatch -> Alarms / Log groups, ECS -> Clusters, EC2 -> Target groups

Para la evidencia del gate de seguridad (opcional):
  ./scripts/demo_gate_seguridad.sh <ruta-a-Flask-Dashboard-S3> "${OUT_DIR}"

Al terminar: ./scripts/down.sh
EOF
