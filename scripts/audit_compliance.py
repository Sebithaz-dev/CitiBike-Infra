"""Audita las politicas de cumplimiento de los repositorios de la EP3.

Comprueba, contra la API de GitHub, los controles que exige IE5:

  * proteccion de la rama main: PR obligatorio, checks requeridos, sin
    force-push, sin borrado, historial lineal y conversaciones resueltas;
  * archivos de gobierno: SECURITY.md, CODEOWNERS y dependabot.yml;
  * analisis de seguridad de GitHub: secret scanning y push protection;
  * ultimo run de cada workflow en main en verde (evidencia de IE6).

Uso:
    python scripts/audit_compliance.py            # tabla en consola
    python scripts/audit_compliance.py --json     # salida para el informe
    python scripts/audit_compliance.py --strict   # un SKIP tambien falla

Token: GITHUB_TOKEN o, en su defecto, `gh auth token`. Para leer la
proteccion de rama hace falta un token con scope de administracion; el
GITHUB_TOKEN de Actions no lo tiene, asi que ese control se marca como SKIP
y solo falla con --strict (uso local, que es donde se audita de verdad).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
DEFAULT_REPOS = (
    "Sebithaz-dev/CitiBike-Infra",
    "Sebithaz-dev/Flask-Dashboard-S3",
    "Sebithaz-dev/Model-Training-S3",
)
REQUIRED_FILES = ("SECURITY.md", ".github/CODEOWNERS", ".github/dependabot.yml")


class Skip(Exception):
    """El control no se puede evaluar con el token actual."""


def token() -> str:
    value = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if value:
        return value
    try:
        return subprocess.run(
            ["gh", "auth", "token"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def api(path: str, token_value: str) -> dict:
    request = urllib.request.Request(API + path)
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    request.add_header("User-Agent", "citibike-compliance-audit")
    if token_value:
        request.add_header("Authorization", f"Bearer {token_value}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403, 404):
            raise Skip(f"HTTP {error.code} ({path})") from error
        raise


def check_branch_protection(repo: str, token_value: str) -> list[tuple[str, bool | None, str]]:
    data = api(f"/repos/{repo}/branches/main/protection", token_value)
    checks = data.get("required_status_checks") or {}
    contexts = checks.get("contexts") or [c.get("context") for c in checks.get("checks", [])]
    results = [
        ("PR obligatorio y checks requeridos", bool(contexts), ", ".join(contexts) or "sin checks"),
        ("Checks al dia antes de mergear (strict)", bool(checks.get("strict")), "strict=false"),
        ("Force-push bloqueado", not data["allow_force_pushes"]["enabled"], "force push permitido"),
        ("Borrado de main bloqueado", not data["allow_deletions"]["enabled"], "deletion permitida"),
        ("Historial lineal", data["required_linear_history"]["enabled"], "merge commits permitidos"),
        (
            "Conversaciones resueltas antes del merge",
            data["required_conversation_resolution"]["enabled"],
            "sin required_conversation_resolution",
        ),
    ]
    return results


def check_secret_scanning(repo: str, token_value: str) -> list[tuple[str, bool | None, str]]:
    data = api(f"/repos/{repo}", token_value)
    analysis = data.get("security_and_analysis") or {}
    secret = analysis.get("secret_scanning") or {}
    push = analysis.get("secret_scanning_push_protection") or {}
    if not secret:
        raise Skip("security_and_analysis no disponible para este token")
    return [
        ("Secret scanning activo", secret.get("status") == "enabled", "deshabilitado"),
        ("Push protection activa", push.get("status") == "enabled", "deshabilitada"),
    ]


def check_files(repo: str, token_value: str) -> list[tuple[str, bool | None, str]]:
    results = []
    for path in REQUIRED_FILES:
        try:
            api(f"/repos/{repo}/contents/{path}", token_value)
            results.append((f"Archivo {path}", True, ""))
        except Skip:
            results.append((f"Archivo {path}", False, "no existe"))
    return results


def check_workflows(repo: str, token_value: str) -> list[tuple[str, bool | None, str]]:
    """Ultimo run en main de cada workflow definido en el repo.

    Se consulta workflow por workflow (y no la lista global de runs) para no
    mezclar los runs de Dependabot, que no son gates del proyecto.
    """
    workflows = api(f"/repos/{repo}/actions/workflows", token_value).get("workflows", [])
    if not workflows:
        raise Skip("sin workflows")
    results: list[tuple[str, bool | None, str]] = []
    for workflow in workflows:
        if workflow.get("state") != "active":
            continue
        runs = api(
            f"/repos/{repo}/actions/workflows/{workflow['id']}/runs?branch=main&per_page=1",
            token_value,
        ).get("workflow_runs", [])
        if not runs:
            results.append((f"Workflow '{workflow['name']}' con run en main", None, "sin runs"))
            continue
        run = runs[0]
        if run.get("status") != "completed":
            results.append(
                (
                    f"Workflow '{workflow['name']}' en main",
                    None,
                    f"en curso ({run.get('status')})",
                )
            )
            continue
        results.append(
            (
                f"Workflow '{workflow['name']}' en verde",
                run.get("conclusion") in ("success", "skipped"),
                f"{run.get('status')}/{run.get('conclusion')} ({run.get('html_url')})",
            )
        )
    return results


CHECKS = (
    ("Proteccion de rama", check_branch_protection),
    ("Archivos de gobierno", check_files),
    ("Analisis de seguridad", check_secret_scanning),
    ("Ultimos workflows en main", check_workflows),
)


def audit(repos: tuple[str, ...], token_value: str) -> dict:
    report: dict[str, list[dict]] = {}
    for repo in repos:
        entries: list[dict] = []
        for group, check in CHECKS:
            try:
                results = check(repo, token_value)
            except Skip as skip:
                entries.append(
                    {"group": group, "name": "no evaluable", "ok": None, "detail": str(skip)}
                )
                continue
            entries += [
                {"group": group, "name": name, "ok": ok, "detail": "" if ok else detail}
                for name, ok, detail in results
            ]
        report[repo] = entries
    return report


def render(report: dict) -> tuple[int, int]:
    total = failures = 0
    for repo, entries in report.items():
        print(f"\n== {repo} ==")
        for entry in entries:
            total += 1
            if entry["ok"] is None:
                mark, extra = " SKIP ", entry["detail"]
            elif entry["ok"]:
                mark, extra = " OK  ", ""
            else:
                mark, extra = "FAIL ", entry["detail"]
                failures += 1
            detail = f"  ({extra})" if extra else ""
            print(f"  [{mark}] {entry['name']}{detail}")
    return total, failures


def render_markdown(report: dict) -> str:
    lines = ["| Repositorio | Control | Estado | Detalle |", "|---|---|---|---|"]
    for repo, entries in report.items():
        for entry in entries:
            state = "SKIP" if entry["ok"] is None else ("OK" if entry["ok"] else "FALLA")
            lines.append(
                f"| {repo} | {entry['name']} | {state} | {entry['detail'].replace('|', '/')} |"
            )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audita el cumplimiento de los repos de la EP3")
    parser.add_argument("--repo", action="append", dest="repos", help="owner/repo (repetible)")
    parser.add_argument("--json", action="store_true", help="emite el informe en JSON")
    parser.add_argument("--markdown", action="store_true", help="emite una tabla Markdown")
    parser.add_argument(
        "--strict", action="store_true", help="trata los SKIP como fallas (uso local)"
    )
    args = parser.parse_args(argv)

    token_value = token()
    if not token_value:
        print("ERROR: falta GITHUB_TOKEN o `gh auth login`.", file=sys.stderr)
        return 2

    report = audit(tuple(args.repos or DEFAULT_REPOS), token_value)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    elif args.markdown:
        print(render_markdown(report))
    else:
        total, failures = render(report)
        skipped = sum(1 for entries in report.values() for e in entries if e["ok"] is None)
        print(f"\nResumen: {total} controles, {failures} fallas, {skipped} no evaluables.")
        if args.strict and skipped:
            print("Modo estricto: los controles no evaluables cuentan como falla.")
            failures += skipped

    if args.strict:
        failures = sum(
            1 for entries in report.values() for e in entries if e["ok"] is not True
        )
    else:
        failures = sum(1 for entries in report.values() for e in entries if e["ok"] is False)

    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
