# Guía de verificación manual (EP3)

Pasos para comprobar **con tus propios ojos** cada indicador, sin depender de lo
que diga otro. Todo se ejecuta desde `CitiBike-Infra/` salvo donde se indique.

## 0. Preparación (2 min)

1. En el Learner Lab: **AWS Details → Show** y copia `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN` a `~/.aws/credentials`.
2. Comprueba que la sesión es válida:

   ```bash
   aws sts get-caller-identity --query Arn --output text
   # arn:aws:sts::690247773624:assumed-role/voclabs/...
   ```

3. Guarda la URL del balanceador:

   ```bash
   export ALB=$(terraform -chdir=terraform output -raw alb_dns_name)
   echo "Dashboard: http://$ALB   Grafana: http://$ALB:3000"
   ```

> Las credenciales del laboratorio duran **4 horas**. Si algo empieza a fallar
> con `ExpiredToken`, vuelve a copiarlas: no es un bug del proyecto.

## 1. Verificación automática (1 min)

```bash
./scripts/verify.sh --wait
```

Debes terminar con `Todo OK.` y exit code 0 (`echo $?`). Comprueba, línea por
línea: 5 servicios ECS en `1/1`, target groups `healthy`, `/health` `/`
`/metrics` en 200, Grafana con `database ok`, ambos datasources y el dashboard
`citibike-ep3` con 4 filas.

## 2. El dashboard unificado (IE1 + IE3)

Abre `http://$ALB:3000` (usuario `admin`, contraseña `citibike-ep3`) y entra a
**Dashboards → CitiBike EP3 - Observabilidad unificada**:

| Fila | Qué deberías ver |
|---|---|
| 1. Disponibilidad | `Dashboard ECS` y `Dashboard Render` en verde; `Servicios ECS corriendo` = 5; línea de `probe_success` por endpoint |
| 2. Errores y latencia | RPS del dashboard, 5xx en 0, p95 estable (ms) |
| 3. Recursos | CPU y memoria del servicio `dashboard` (Container Insights) + CPU y memoria de **la instancia** (AWS/EC2 y CWAgent) |
| 4. CI/CD y modelo | Duración del despliegue (último `deploy.sh`), cobertura de tests y `Quality gate` |

Para generar tráfico y ver las gráficas moverse:

```bash
for i in $(seq 1 30); do curl -s -o /dev/null http://$ALB/predict; curl -s -o /dev/null http://$ALB/; done
```

## 3. Métricas del microservicio en vivo (IE1)

```bash
curl -s http://$ALB/metrics | grep -E "^flask_http_request_total|^citibike_" | head
```

Y en Prometheus (a través del proxy de Grafana, sin exponer el puerto 9090):

```bash
curl -s -u admin:citibike-ep3 \
  "http://$ALB:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" \
  | python3 -m json.tool | head -30
```

Deben aparecer 5 series con `value: ["...","1"]`: `dashboard`, `prometheus` y
tres probes de `blackbox` (dashboard local, Grafana y Render).

## 4. Logs (IE1)

Consola → **CloudWatch → Log groups**, abre `/ecs/citibike-dev/dashboard` y
mira el último stream. O por CLI:

```bash
aws logs tail /ecs/citibike-dev/dashboard --since 10m --follow
```

Hay un grupo por servicio (`dashboard`, `prometheus`, `grafana`,
`alertmanager`, `blackbox`), con retención de 7 días.

## 5. Alarmas (IE1 + IE6)

```bash
aws cloudwatch describe-alarms --alarm-name-prefix citibike-dev \
  --query 'MetricAlarms[].[AlarmName,StateValue,MetricName]' --output table
```

Las 7 deben estar en `OK`. Reglas de Prometheus (desde Grafana → Alerting, o por
API):

```bash
curl -s -u admin:citibike-ep3 \
  "http://$ALB:3000/api/datasources/proxy/uid/prometheus/api/v1/rules" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);[print(r['name'],r['state']) for g in d['data']['groups'] for r in g['rules']]"
```

### Provocar una falla controlada (opcional, 5 min)

```bash
aws ecs update-service --cluster citibike-dev-cluster --service dashboard --desired-count 0
# espera ~2-3 min y mira la alarma y la fila 1 del dashboard
aws cloudwatch describe-alarms --alarm-name citibike-dev-dashboard-unhealthy \
  --query 'MetricAlarms[0].StateValue' --output text     # -> ALARM
aws ecs update-service --cluster citibike-dev-cluster --service dashboard --desired-count 1
```

Es la forma más rápida de ver la observabilidad "en acción": la alarma cambia
de estado, `probe_success` cae a 0 y la fila 1 se pone roja. **Recuerda
devolver el servicio a 1 tarea.**

## 6. El pipeline se detiene (IE6)

En `Flask-Dashboard-S3`, sobre una rama nueva:

```bash
git checkout -b demo/gate
printf 'def test_falla():\n    assert False\n' > tests/test_demo_gate.py
git add . && git commit -m "demo: test que falla" && git push -u origin demo/gate
gh pr create --title "demo: gate" --body "no mergear"
```

Verás `Run tests` en rojo, `SonarCloud` en rojo, los jobs de build/deploy en
`skipping` y el PR en **`BLOCKED`** (`gh pr view --json mergeStateStatus`).
Cierra el PR y borra la rama al terminar. La captura de esta prueba está en
`docs/evidence/*/ie6-gate-bloqueante.txt`.

## 7. Medir un despliegue (IE2 + IE3)

```bash
./scripts/deploy.sh latest
```

Imprime `Despliegue estable en Ns` y publica `DeploymentDurationSeconds` en
`CitiBike/CI`; el panel "Duración del despliegue" se actualiza solo. Referencia:
**126-127 s** con este stack.

## 8. Auditoría de cumplimiento (IE5)

```bash
python3 scripts/audit_compliance.py --strict        # 47 controles, 0 fallas
python3 scripts/audit_compliance.py --strict --markdown > auditoria.md
```

Sin `--strict` es lo que corre en CI (el `GITHUB_TOKEN` no puede leer la
protección de rama). En local, con el token de `gh auth`, se audita todo.

## 9. Evidencia y cierre

```bash
./scripts/collect_evidence.sh     # -> docs/evidence/<fecha>/
./scripts/down.sh                 # destruye todo lo que creó Terraform
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text   # debe estar vacío
```

## Problemas esperables

| Síntoma | Causa | Acción |
|---|---|---|
| `ExpiredToken` | sesión de 4 h agotada | copiar credenciales nuevas |
| `verify.sh` en rojo tras un rato sin usar | el laboratorio suspende la instancia | esperar 2 min y repetir con `--wait` |
| Grafana 502 | la task de Grafana está arrancando | `aws ecs wait services-stable --cluster citibike-dev-cluster --services grafana` |
| Panel de CloudWatch vacío | recién desplegado (las métricas tardan ~2 min) | esperar y refrescar |
