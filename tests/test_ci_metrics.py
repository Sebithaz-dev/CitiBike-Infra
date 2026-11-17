"""Tests de scripts/ci_metrics.py (sin AWS)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import ci_metrics  # noqa: E402


def _args(**kwargs):
    base = {
        "coverage": None,
        "tests_passed": None,
        "tests_failed": None,
        "deployment_seconds": None,
        "gate_status": None,
    }
    base.update(kwargs)
    return type("Args", (), base)


def test_build_metrics_completo():
    data = ci_metrics.build_metrics(
        _args(
            coverage=84.05,
            tests_passed=28,
            tests_failed=0,
            deployment_seconds=95.5,
            gate_status="pass",
        )
    )
    nombres = {d["MetricName"]: d["Value"] for d in data}

    assert nombres["TestCoveragePercent"] == 84.05
    assert nombres["DeploymentDurationSeconds"] == 95.5
    assert nombres["QualityGatePassed"] == 1.0


def test_build_metrics_gate_fallido():
    data = ci_metrics.build_metrics(_args(gate_status="fail"))
    gate = next(d for d in data if d["MetricName"] == "QualityGatePassed")

    assert gate["Value"] == 0.0


def test_dry_run_no_requiere_aws(capsys):
    code = ci_metrics.main(["--coverage", "84", "--dry-run"])

    assert code == 0
    assert "TestCoveragePercent=84.0" in capsys.readouterr().out


def test_sin_metricas_devuelve_error():
    assert ci_metrics.main(["--dry-run"]) == 1
