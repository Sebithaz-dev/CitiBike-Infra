#!/usr/bin/env bash
# IE6: demuestra que una vulnerabilidad de severidad alta detiene el pipeline.
#
# Crea en Flask-Dashboard-S3 un PR que agrega una dependencia con
# vulnerabilidades criticas conocidas (django==2.2), espera los checks, guarda el
# resultado y el estado de merge (debe ser BLOCKED) y luego CIERRA el PR y
# borra la rama sin mergear.
#
# Uso:
#   ./scripts/demo_gate_seguridad.sh <ruta-a-Flask-Dashboard-S3> [carpeta-evidencia]
#
# Requisitos: gh autenticado con permiso de push en el repo.
set -euo pipefail

REPO_DIR="${1:?Uso: $0 <ruta-a-Flask-Dashboard-S3> [carpeta-evidencia]}"
OUT_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/docs/evidence/$(date -u +%Y%m%dT%H%M%SZ)}"
BRANCH="demo/gate-seguridad-$(date -u +%Y%m%d%H%M%S)"
# Dependencia con vulnerabilidades criticas que no choca con flask==3.1.3:
# pip la instala sin conflictos y el check falla por Snyk, no por pip.
VULN_DEP="django==2.2"
mkdir -p "$OUT_DIR"
OUT_FILE="$(cd "$OUT_DIR" && pwd)/ie6-gate-seguridad.txt"

cd "$REPO_DIR"
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: $REPO_DIR tiene cambios sin commitear." >&2
  exit 1
fi

git fetch -q origin main
git checkout -q -b "$BRANCH" origin/main
# requirements.txt puede no terminar en salto de linea.
[ -z "$(tail -c1 requirements.txt)" ] || echo >> requirements.txt
echo "$VULN_DEP" >> requirements.txt
git add requirements.txt
git commit -q -m "demo: dependencia vulnerable para probar el gate de seguridad (no mergear)"
git push -q -u origin "$BRANCH"

pr_url="$(gh pr create --base main --head "$BRANCH" \
  --title "demo: el gate de seguridad bloquea el merge (no mergear)" \
  --body "PR de demostracion para la EP3 (IE6): agrega ${VULN_DEP}, con vulnerabilidades criticas conocidas. Se cierra sin mergear.")"
echo "PR: $pr_url"

echo "Esperando los checks (puede tardar varios minutos)..."
gh pr checks "$pr_url" --watch --interval 30 >/dev/null 2>&1 || true

{
  echo "PR: $pr_url"
  echo "Titulo: demo: el gate de seguridad bloquea el merge (no mergear)"
  echo "Cambio: requirements.txt + ${VULN_DEP}"
  echo "estado de merge: $(gh pr view "$pr_url" --json mergeStateStatus --jq .mergeStateStatus)"
  gh pr checks "$pr_url" || true
} | tee "$OUT_FILE"

gh pr close "$pr_url" --delete-branch --comment "Demo terminada: evidencia guardada. Se cierra sin mergear."
git checkout -q main
git branch -D "$BRANCH" >/dev/null 2>&1 || true

echo
echo "Evidencia: $OUT_FILE"
echo "El paso esperado es 'Snyk (SCA + Code)' en fail y el estado de merge BLOCKED."
