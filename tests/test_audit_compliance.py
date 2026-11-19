"""Tests de scripts/audit_compliance.py (sin llamadas a GitHub)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import audit_compliance  # noqa: E402

REPORT = {
    "owner/repo": [
        {"group": "Archivos", "name": "SECURITY.md", "ok": True, "detail": ""},
        {"group": "Rama", "name": "Force-push bloqueado", "ok": False, "detail": "permitido"},
        {"group": "Rama", "name": "Proteccion", "ok": None, "detail": "HTTP 403"},
    ]
}


def test_render_cuenta_fallas():
    total, failures = audit_compliance.render(REPORT)
    assert total == 3
    assert failures == 1


def test_render_markdown_marca_estados():
    tabla = audit_compliance.render_markdown(REPORT)
    assert "| OK |" in tabla
    assert "| FALLA |" in tabla
    assert "| SKIP |" in tabla
    assert tabla.startswith("| Repositorio |")


def test_audit_marca_skip_cuando_falta_permiso(monkeypatch):
    def deny(repo, token):
        raise audit_compliance.Skip("HTTP 403")

    monkeypatch.setattr(audit_compliance, "CHECKS", (("Rama", deny),))
    report = audit_compliance.audit(("owner/repo",), "token")
    assert report["owner/repo"][0]["ok"] is None
    assert "403" in report["owner/repo"][0]["detail"]


def test_main_sin_token_devuelve_error(monkeypatch, capsys):
    monkeypatch.setattr(audit_compliance, "token", lambda: "")
    assert audit_compliance.main([]) == 2
    assert "GITHUB_TOKEN" in capsys.readouterr().err


def test_main_strict_falla_con_skip(monkeypatch):
    monkeypatch.setattr(audit_compliance, "token", lambda: "t")
    monkeypatch.setattr(audit_compliance, "audit", lambda repos, token: REPORT)
    assert audit_compliance.main(["--strict"]) == 1
    assert audit_compliance.main([]) == 1
