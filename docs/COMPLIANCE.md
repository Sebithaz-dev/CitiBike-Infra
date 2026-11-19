# Cumplimiento y auditoría automatizada (EP3)

Este documento describe las políticas de cumplimiento que se aplican sobre los
tres repositorios del proyecto, la herramienta que las audita y la evidencia
que deja cada corrida. Cubre los indicadores **IE5** (políticas de
cumplimiento) e **IE6** (el pipeline se detiene ante fallas críticas).

## 1. Alcance

| Repositorio | Rol en el proyecto | Rama protegida |
|---|---|---|
| `Sebithaz-dev/Model-Training-S3` | Entrenamiento, quality gate del modelo y publicación de artefactos | `main` |
| `Sebithaz-dev/Flask-Dashboard-S3` | Microservicio que consume el parquet curado y expone `/health`, `/` y `/metrics` | `main` |
| `Sebithaz-dev/CitiBike-Infra` | Infraestructura ECS, Prometheus, Grafana, alarmas y scripts de operación | `main` |

## 2. Controles implementados

| # | Control | Herramienta | Dónde se aplica | Indicador |
|---|---|---|---|---|
| C1 | PR obligatorio hacia `main`, sin push directo | Branch protection | Los 3 repos | IE5 |
| C2 | Checks requeridos y **estrictos** (`strict = true`: la rama debe estar al día) | Branch protection | Los 3 repos | IE5, IE6 |
| C3 | Force-push y borrado de `main` bloqueados | Branch protection | Los 3 repos | IE5 |
| C4 | Historial lineal y conversaciones resueltas antes del merge | Branch protection | Los 3 repos | IE5 |
| C5 | Revisión de código por dueños del área | `CODEOWNERS` | Los 3 repos | IE5 |
| C6 | Dependencias actualizadas de forma controlada (majors revisados a mano, minor/patch agrupados) | `dependabot.yml` | Los 3 repos | IE5 |
| C7 | Reporte de vulnerabilidades | `SECURITY.md` | Los 3 repos | IE5 |
| C8 | Secret scanning y push protection | GitHub Advanced Security | Los 3 repos | IE5 |
| C9 | SAST + dependencias: Snyk y SonarCloud | `security.yml` / `ci-cd.yml` | Flask | IE5, IE6 |
| C10 | Cobertura mínima de tests como gate (`--cov-fail-under`) | pytest-cov | Model-Training (60 %), Flask (70 %) | IE6 |
| C11 | Quality gate del modelo (ROC-AUC, MAE, tamaño de muestra) antes de publicar en S3 | `ml/quality_gate.py` + `config/quality_gate.yaml` | Model-Training | IE6 |
| C12 | `terraform fmt`, `terraform validate` y validación de configs de monitoreo | `infra-ci.yml` | CitiBike-Infra | IE6 |
| C13 | Auditoría de cumplimiento automática | `scripts/audit_compliance.py` | CitiBike-Infra (local + CI) | IE5 |

### Por qué la auditoría corre en dos modos

El endpoint de GitHub que devuelve la protección de rama exige permisos de
administración. El `GITHUB_TOKEN` de Actions no los tiene, así que en CI el
auditor corre en **modo no estricto**: verifica archivos de gobierno, secret
scanning y el estado de los workflows, y marca la protección de rama como
`SKIP`. En la sesión de operación se ejecuta en **modo estricto** con el token
de `gh auth` (que sí tiene scope de administración), y ahí un `SKIP` cuenta
como falla. El resultado de esa corrida es la evidencia que se adjunta al
informe.

```bash
# Auditoría completa (evidencia para el informe)
python3 scripts/audit_compliance.py --strict

# Tabla Markdown para pegar en el informe
python3 scripts/audit_compliance.py --strict --markdown

# Solo lo que el GITHUB_TOKEN puede ver (lo que corre en CI)
python3 scripts/audit_compliance.py
```

## 3. Cómo el pipeline se detiene (IE6)

| Falla | Qué la detecta | Efecto |
|---|---|---|
| Test roto o cobertura bajo el umbral | job `Run tests` / `Lint y tests` | El check requerido queda rojo y el merge está bloqueado |
| Vulnerabilidad alta en dependencias o código | `Snyk (SCA + Code)` | Check requerido rojo |
| Deuda de calidad sobre el umbral | `SonarCloud` | Check requerido rojo |
| Modelo por debajo del umbral de calidad | `ml/quality_gate.py` | `ml.train` no sube artefactos a S3 y el workflow falla |
| Infraestructura inválida | `Terraform fmt + validate`, `Validar configs de monitoreo` | Check requerido rojo |
| Credenciales AWS ausentes o expiradas | preflight de `train.yml` | El job se omite en verde con warning (no confunde "sin credenciales" con "falla real") |
| Servicio caído en producción | alarma `*-dashboard-unhealthy` + regla `DashboardDown` | Alarma en estado `ALARM` visible en CloudWatch y Grafana |

## 4. Evidencia de la última auditoría

La salida completa se guarda con `./scripts/collect_evidence.sh` en
`docs/evidence/<fecha>/compliance.md`. La corrida del **2026-11-19** sobre los
tres repositorios dio **47 controles, 0 fallas, 0 no evaluables** (modo
estricto), incluyendo protección de rama, secret scanning y push protection
activos en los tres repos.

El propio check **`Auditoria de cumplimiento`** es requerido en `main`
(`infra-ci.yml` + `compliance.yml`), así que una regresión de gobierno bloquea
el merge igual que un test rojo.

## 5. Referencias normativas

- ISO/IEC 27001:2022, controles 8.25–8.32 (ciclo de vida seguro del software,
  gestión de vulnerabilidades, segregación de ambientes).
- OWASP SAMM: prácticas de *Secure Build* y *Environment Management*.
- Ley 21.719 (Chile, protección de datos personales): los datos de Citi Bike se
  tratan de forma agregada y no se publican identificadores personales; el
  bucket mantiene acceso privado.
