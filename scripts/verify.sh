#!/usr/bin/env bash
# Verifica el despliegue EP3 sobre ECS y resume la evidencia en consola.
#
# Uso:
#   ./scripts/verify.sh          # valida el estado actual
#   ./scripts/verify.sh --wait   # espera a que los servicios esten estables
#
# Requiere credenciales AWS validas exportadas en el shell y el state de
# Terraform (o DASHBOARD_URL / GRAFANA_URL definidos a mano).

set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${ECS_CLUSTER:-citibike-dev-cluster}"
TG_PREFIX="${TG_PREFIX:-citibike-dev}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-citibike-ep3}"
WAIT=0
[ "${1:-}" = "--wait" ] && WAIT=1

fails=0
ok() { printf '  [ OK ] %s\n' "$*"; }
ko() { printf '  [FAIL] %s\n' "$*"; fails=$((fails + 1)); }
title() { printf '\n== %s ==\n' "$*"; }

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: falta curl." >&2
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: credenciales AWS invalidas o expiradas." >&2
  echo "Copia las credenciales de la sesion del Learner Lab y vuelve a intentar." >&2
  exit 1
fi

if [ "$WAIT" = 1 ]; then
  title "Esperando servicios estables"
  aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" \
    --services dashboard prometheus grafana alertmanager blackbox
  ok "servicios estables"
fi

# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------
title "Servicios ECS (cluster ${CLUSTER})"
for svc in dashboard prometheus grafana alertmanager blackbox; do
  read -r status running desired rollout < <(
    aws ecs describe-services --region "$REGION" --cluster "$CLUSTER" --services "$svc" \
      --query 'services[0].[status,runningCount,desiredCount,deployments[0].rolloutState]' \
      --output text 2>/dev/null || echo "MISSING 0 0 -"
  )
  if [ "$status" = "ACTIVE" ] && [ "$running" = "$desired" ] && [ "$desired" != "0" ]; then
    ok "${svc}: ${running}/${desired} tareas (${rollout})"
  else
    ko "${svc}: status=${status} tareas=${running}/${desired} rollout=${rollout}"
  fi
done

# ---------------------------------------------------------------------------
# Target groups del ALB
# ---------------------------------------------------------------------------
title "Target groups del ALB"
if tgs=$(aws elbv2 describe-target-groups --region "$REGION" \
  --names "${TG_PREFIX}-dash" "${TG_PREFIX}-graf" \
  --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null); then
  for arn in $tgs; do
    name=$(aws elbv2 describe-target-groups --region "$REGION" --target-group-arns "$arn" \
      --query 'TargetGroups[0].TargetGroupName' --output text)
    state=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$arn" \
      --query 'TargetHealthDescriptions[].TargetHealth.State' --output text)
    if [ "$state" = "healthy" ]; then
      ok "${name}: healthy"
    else
      ko "${name}: ${state:-sin targets registrados}"
    fi
  done
else
  ko "no se encontraron los target groups ${TG_PREFIX}-dash / ${TG_PREFIX}-graf"
fi

# ---------------------------------------------------------------------------
# Endpoints publicos
# ---------------------------------------------------------------------------
DASHBOARD_URL="${DASHBOARD_URL:-$(terraform -chdir=terraform output -raw dashboard_url 2>/dev/null || true)}"
GRAFANA_URL="${GRAFANA_URL:-$(terraform -chdir=terraform output -raw grafana_url 2>/dev/null || true)}"

check_http() { # nombre url patron(opcional)
  local name="$1" url="$2" pattern="${3:-}" body
  if ! body=$(curl -fsS --max-time 20 "$url" 2>/dev/null); then
    ko "${name} -> ${url} inaccesible"
    return
  fi
  if [ -n "$pattern" ] && ! printf '%s' "$body" | grep -q "$pattern"; then
    ko "${name} -> 200 pero sin '${pattern}'"
    return
  fi
  ok "${name} -> 200"
}

title "Dashboard Flask"
if [ -n "$DASHBOARD_URL" ]; then
  check_http "/health" "${DASHBOARD_URL}/health" '"status": *"ok"'
  check_http "/" "${DASHBOARD_URL}/" "<html"
  check_http "/metrics" "${DASHBOARD_URL}/metrics" "flask_http_request_total"
else
  ko "sin URL del dashboard (terraform output dashboard_url)"
fi

# ---------------------------------------------------------------------------
# Grafana (API con basic auth)
# ---------------------------------------------------------------------------
grafana_json() { curl -fsS --max-time 20 -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}$1"; }

title "Grafana"
if [ -n "$GRAFANA_URL" ]; then
  if health=$(grafana_json /api/health 2>/dev/null) &&
    printf '%s' "$health" | grep -q '"database": *"ok"'; then
    ok "/api/health: database ok"
  else
    ko "/api/health: ${health:-sin respuesta}"
  fi

  if ds=$(grafana_json /api/datasources 2>/dev/null); then
    while IFS=$'\t' read -r uid name; do
      if dh=$(grafana_json "/api/datasources/uid/${uid}/health" 2>/dev/null) &&
        printf '%s' "$dh" | grep -q '"status": *"OK"'; then
        ok "datasource ${name}"
      else
        ko "datasource ${name}: ${dh:-sin respuesta}"
      fi
    done < <(printf '%s' "$ds" |
      python3 -c 'import json,sys;[print(d["uid"], d["name"], sep="\t") for d in json.load(sys.stdin)]')
  else
    ko "no se pudieron listar los datasources"
  fi

  if dash=$(grafana_json /api/dashboards/uid/citibike-ep3 2>/dev/null); then
    rows=$(printf '%s' "$dash" | python3 -c \
      'import json,sys;d=json.load(sys.stdin);print(sum(1 for p in d["dashboard"].get("panels",[]) if p.get("type")=="row"))' \
      2>/dev/null || echo 0)
    if [ "$rows" = "4" ]; then
      ok "dashboard citibike-ep3: 4 filas"
    else
      ko "dashboard citibike-ep3: ${rows} filas (esperadas 4)"
    fi
  else
    ko "dashboard citibike-ep3 no encontrado"
  fi
else
  ko "sin URL de Grafana (terraform output grafana_url)"
fi

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
title "Resumen"
if [ "$fails" -eq 0 ]; then
  echo "  Todo OK."
  exit 0
fi
echo "  ${fails} verificacion(es) fallaron."
exit 1
