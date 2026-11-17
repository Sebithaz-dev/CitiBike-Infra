"""Publica metricas del pipeline CI/CD en CloudWatch (namespace CitiBike/CI).

Alimenta los paneles de IE3: duracion del despliegue, cobertura de tests,
tests aprobados/fallidos y estado del quality gate.

Uso:
    python scripts/ci_metrics.py --coverage 84.05 --tests-passed 28
    python scripts/ci_metrics.py --deployment-seconds 95 --gate-status pass

Sin permisos AWS el script falla con exit code 1 para que el pipeline lo
note; usar --dry-run para imprimir las metricas sin publicarlas.
"""
from __future__ import annotations

import argparse
import os
import sys

DEFAULT_NAMESPACE = "CitiBike/CI"


def build_metrics(args: argparse.Namespace) -> list[dict]:
    data: list[dict] = []
    if args.coverage is not None:
        data.append(
            {
                "MetricName": "TestCoveragePercent",
                "Value": float(args.coverage),
                "Unit": "Percent",
            }
        )
    if args.tests_passed is not None:
        data.append({"MetricName": "TestsPassed", "Value": float(args.tests_passed), "Unit": "Count"})
    if args.tests_failed is not None:
        data.append({"MetricName": "TestsFailed", "Value": float(args.tests_failed), "Unit": "Count"})
    if args.deployment_seconds is not None:
        data.append(
            {
                "MetricName": "DeploymentDurationSeconds",
                "Value": float(args.deployment_seconds),
                "Unit": "Seconds",
            }
        )
    if args.gate_status is not None:
        data.append(
            {
                "MetricName": "QualityGatePassed",
                "Value": 1.0 if args.gate_status == "pass" else 0.0,
                "Unit": "None",
            }
        )
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Publica metricas CI/CD en CloudWatch")
    parser.add_argument("--coverage", type=float, help="Cobertura de tests en porcentaje")
    parser.add_argument("--tests-passed", type=int, dest="tests_passed")
    parser.add_argument("--tests-failed", type=int, dest="tests_failed")
    parser.add_argument("--deployment-seconds", type=float, dest="deployment_seconds")
    parser.add_argument("--gate-status", choices=["pass", "fail"], dest="gate_status")
    parser.add_argument("--namespace", default=os.getenv("CLOUDWATCH_NAMESPACE", DEFAULT_NAMESPACE))
    parser.add_argument("--region", default=os.getenv("AWS_REGION", "us-east-1"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    data = build_metrics(args)
    if not data:
        print("Nada que publicar: pasa al menos una metrica.")
        return 1

    if args.dry_run:
        print(f"Namespace: {args.namespace}")
        for item in data:
            print(f"  {item['MetricName']}={item['Value']} ({item['Unit']})")
        return 0

    import boto3

    client = boto3.client("cloudwatch", region_name=args.region)
    client.put_metric_data(Namespace=args.namespace, MetricData=data)
    print(f"{len(data)} metricas publicadas en {args.namespace}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
