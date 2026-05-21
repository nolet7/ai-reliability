#!/usr/bin/env python3
"""
Phase 11 - Dynatrace SLO Catalog Metric Publisher

Purpose:
  Measure the AS AI Reliability POC SLO catalog and publish the results
  into Dynatrace as custom metrics.

This script measures:
  - runtime availability
  - model health readiness
  - model version compliance
  - prediction success rate
  - prediction latency compliance
  - canary/rollback route readiness
  - ServiceNow incident automation readiness
  - evidence-pack readiness
  - overall AI reliability score
"""

from __future__ import annotations

import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/dynatrace-slo-catalog"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "dynatrace-slo-catalog-summary.md"
JSON_REPORT = REPORT_ROOT / "dynatrace-slo-catalog-report.json"
METRIC_LINES_FILE = REPORT_ROOT / "dynatrace-metric-lines.txt"

RAW_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


APP_NAME = env("APP_NAME", "as-ai-quality-service")
SERVICE_NAME = env("SERVICE_NAME", APP_NAME)
ENVIRONMENT = env("ENVIRONMENT", "poc")
EXPECTED_MODEL_VERSION = env("EXPECTED_MODEL_VERSION", "v1.0.3")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://139.144.255.92").rstrip("/")

DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

SLO_SAMPLE_COUNT = int(env("SLO_SAMPLE_COUNT", "10"))
SLO_LATENCY_THRESHOLD_MS = int(env("SLO_LATENCY_THRESHOLD_MS", "1000"))

PREDICT_PAYLOAD = json.loads(
    env(
        "PREDICT_PAYLOAD",
        json.dumps(
            {
                "asset_id": "asset-1001",
                "site_id": "site-asr-poc-001",
                "sensor_score": 87.5,
                "audit_required": True,
            }
        ),
    )
)


def now_ms() -> int:
    return int(time.time() * 1000)


def safe_dim(value: str) -> str:
    value = str(value)
    for bad in [",", "=", " ", "\n", "\r", "\t"]:
        value = value.replace(bad, "_")
    return value


def percentile(values: List[float], pct: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    index = int(round((pct / 100.0) * (len(values) - 1)))
    return float(values[index])


def http_request(
    method: str,
    path: str,
    payload: Dict[str, Any] | None = None,
    headers: Dict[str, str] | None = None,
) -> Dict[str, Any]:
    url = f"{PUBLIC_BASE_URL}{path}"
    request_headers = headers or {}

    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request_headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url=url,
        data=body,
        headers=request_headers,
        method=method,
    )

    started = time.perf_counter()

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            elapsed_ms = (time.perf_counter() - started) * 1000
            body_text = response.read().decode("utf-8", errors="replace")
            status_code = response.getcode()
    except urllib.error.HTTPError as exc:
        elapsed_ms = (time.perf_counter() - started) * 1000
        body_text = exc.read().decode("utf-8", errors="replace")
        status_code = exc.code
    except Exception as exc:
        elapsed_ms = (time.perf_counter() - started) * 1000
        return {
            "path": path,
            "method": method,
            "status_code": 0,
            "latency_ms": elapsed_ms,
            "success": False,
            "json": {},
            "error": str(exc),
        }

    try:
        parsed = json.loads(body_text) if body_text else {}
    except Exception:
        parsed = {"raw": body_text}

    return {
        "path": path,
        "method": method,
        "status_code": status_code,
        "latency_ms": elapsed_ms,
        "success": 200 <= status_code < 300,
        "json": parsed,
        "error": "",
    }


def extract_model_version(data: Dict[str, Any]) -> str:
    for key in ["model_version", "modelVersion", "version"]:
        value = data.get(key)
        if isinstance(value, str):
            return value

    model = data.get("model")
    if isinstance(model, dict):
        value = model.get("version") or model.get("model_version")
        if isinstance(value, str):
            return value

    nested = data.get("data")
    if isinstance(nested, dict):
        value = nested.get("model_version") or nested.get("version")
        if isinstance(value, str):
            return value

    return ""


def metric_line(metric: str, value: float, slo_id: str, extra_dims: Dict[str, str] | None = None) -> str:
    dims = {
        "app": APP_NAME,
        "service": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "slo_id": slo_id,
    }

    if extra_dims:
        dims.update(extra_dims)

    dim_text = ",".join(f"{safe_dim(k)}={safe_dim(v)}" for k, v in dims.items())

    # Dynatrace metric ingestion line protocol.
    # Gauge value is published as a single data point.
    return f"{metric},{dim_text} gauge,{float(value):.4f} {now_ms()}"


def ingest_dynatrace_metrics(lines: List[str]) -> Tuple[int, str]:
    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN missing"

    url = f"{DYNATRACE_ENV_URL}/api/v2/metrics/ingest"
    body = ("\n".join(lines) + "\n").encode("utf-8")

    request = urllib.request.Request(
        url=url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Api-Token {DYNATRACE_API_TOKEN}",
            "Content-Type": "text/plain; charset=utf-8",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            response_body = response.read().decode("utf-8", errors="replace")
            return response.getcode(), response_body
    except urllib.error.HTTPError as exc:
        response_body = exc.read().decode("utf-8", errors="replace")
        return exc.code, response_body
    except Exception as exc:
        return 0, str(exc)


def bool_percent(value: bool) -> float:
    return 100.0 if value else 0.0


def main() -> int:
    started_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    endpoint_results: List[Dict[str, Any]] = []

    # Runtime and model endpoints.
    for name, path in [
        ("health_live", "/health/live"),
        ("health_ready", "/health/ready"),
        ("health_model", "/health/model"),
        ("version", "/version"),
    ]:
        result = http_request("GET", path)
        result["name"] = name
        endpoint_results.append(result)
        (RAW_DIR / f"{name}.json").write_text(json.dumps(result, indent=2), encoding="utf-8")

    # Predict samples.
    predict_results: List[Dict[str, Any]] = []

    for i in range(SLO_SAMPLE_COUNT):
        result = http_request(
            "POST",
            "/predict",
            payload=PREDICT_PAYLOAD,
            headers={"x-trace-id": f"dynatrace-slo-catalog-{i + 1}"},
        )
        result["name"] = "predict"
        result["sample"] = i + 1
        predict_results.append(result)
        (RAW_DIR / f"predict_{i + 1}.json").write_text(json.dumps(result, indent=2), encoding="utf-8")

    live = next(r for r in endpoint_results if r["name"] == "health_live")
    ready = next(r for r in endpoint_results if r["name"] == "health_ready")
    health_model = next(r for r in endpoint_results if r["name"] == "health_model")
    version = next(r for r in endpoint_results if r["name"] == "version")

    version_model = extract_model_version(version["json"])
    health_model_version = extract_model_version(health_model["json"])

    predict_successes = [r for r in predict_results if r["success"]]
    predict_latencies = [float(r["latency_ms"]) for r in predict_results]
    predict_p95 = percentile(predict_latencies, 95)

    predict_versions = [extract_model_version(r["json"]) for r in predict_results]
    predict_version_matches = [v == EXPECTED_MODEL_VERSION for v in predict_versions]

    runtime_availability = (
        sum(1 for r in [live, ready, version] if r["success"]) / 3.0
    ) * 100.0

    model_health_readiness = bool_percent(health_model["success"])

    model_version_checks = [
        version_model == EXPECTED_MODEL_VERSION,
        *predict_version_matches,
    ]
    model_version_compliance = (
        sum(1 for ok in model_version_checks if ok) / len(model_version_checks)
    ) * 100.0

    prediction_success_rate = (
        len(predict_successes) / max(1, len(predict_results))
    ) * 100.0

    prediction_latency_compliance = (
        sum(1 for ms in predict_latencies if ms <= SLO_LATENCY_THRESHOLD_MS)
        / max(1, len(predict_latencies))
    ) * 100.0

    canary_route_readiness = bool_percent(
        version["success"] and version_model == EXPECTED_MODEL_VERSION
    )

    incident_automation_readiness = bool_percent(
        Path("scripts/incident/servicenow_incident_on_failure.py").exists()
        and Path(".github/workflows/05-servicenow-incident-on-failure.yml").exists()
    )

    evidence_pack_readiness = bool_percent(
        Path(".github/workflows/07-enterprise-poc-evidence-pack.yml").exists()
        and Path(".github/workflows/08-final-demo-interview-pack.yml").exists()
        and Path(".github/workflows/09-final-enterprise-release-certification.yml").exists()
    )

    observability_readiness_pre_ingest = bool_percent(
        bool(DYNATRACE_ENV_URL) and bool(DYNATRACE_API_TOKEN)
    )

    slo_values = {
        "runtime_availability": runtime_availability,
        "model_health_readiness": model_health_readiness,
        "model_version_compliance": model_version_compliance,
        "prediction_success_rate": prediction_success_rate,
        "prediction_latency_compliance": prediction_latency_compliance,
        "canary_route_readiness": canary_route_readiness,
        "incident_automation_readiness": incident_automation_readiness,
        "observability_readiness": observability_readiness_pre_ingest,
        "evidence_pack_readiness": evidence_pack_readiness,
    }

    overall_ai_reliability_score = statistics.mean(slo_values.values())
    slo_values["overall_ai_reliability_score"] = overall_ai_reliability_score

    metric_lines: List[str] = []

    for slo_id, value in slo_values.items():
        metric_lines.append(metric_line("asr.ai.slo.value", value, slo_id))

    metric_lines.append(metric_line("asr.ai.slo.predict.p95_ms", predict_p95, "prediction_latency_p95"))
    metric_lines.append(metric_line("asr.ai.slo.predict.sample_count", SLO_SAMPLE_COUNT, "prediction_sample_count"))
    metric_lines.append(metric_line("asr.ai.slo.model.version_match", bool_percent(version_model == EXPECTED_MODEL_VERSION), "model_version_match"))

    # Per-endpoint raw signals.
    for result in endpoint_results:
        endpoint = result["path"]
        metric_lines.append(
            metric_line(
                "asr.ai.slo.endpoint.success",
                bool_percent(result["success"]),
                "endpoint_success",
                {"endpoint": endpoint, "method": result["method"]},
            )
        )
        metric_lines.append(
            metric_line(
                "asr.ai.slo.endpoint.latency_ms",
                result["latency_ms"],
                "endpoint_latency",
                {"endpoint": endpoint, "method": result["method"]},
            )
        )

    METRIC_LINES_FILE.write_text("\n".join(metric_lines) + "\n", encoding="utf-8")

    status_code, ingest_response = ingest_dynatrace_metrics(metric_lines)
    (RAW_DIR / "dynatrace_ingest_response.txt").write_text(
        f"HTTP_STATUS={status_code}\n{ingest_response}\n",
        encoding="utf-8",
    )

    ingest_success = 200 <= status_code < 300

    report = {
        "phase": "Phase 11 - Dynatrace SLO Catalog Measurement",
        "generated_utc": started_utc,
        "app_name": APP_NAME,
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "public_base_url": PUBLIC_BASE_URL,
        "expected_model_version": EXPECTED_MODEL_VERSION,
        "slo_sample_count": SLO_SAMPLE_COUNT,
        "latency_threshold_ms": SLO_LATENCY_THRESHOLD_MS,
        "version_model": version_model,
        "health_model_version": health_model_version,
        "predict_p95_ms": predict_p95,
        "slo_values": slo_values,
        "dynatrace_ingest_http_status": status_code,
        "dynatrace_ingest_success": ingest_success,
    }

    JSON_REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

    lines = [
        "# Dynatrace SLO Catalog Measurement Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| Public Base URL | {PUBLIC_BASE_URL} |",
        f"| Expected Model Version | {EXPECTED_MODEL_VERSION} |",
        f"| /version Model Version | {version_model or 'not-found'} |",
        f"| /health/model Model Version | {health_model_version or 'not-found'} |",
        f"| Predict p95 Latency | {predict_p95:.2f} ms |",
        f"| Dynatrace Ingest HTTP Status | {status_code} |",
        f"| Dynatrace Ingest Success | {ingest_success} |",
        "",
        "## SLO Values Published to Dynatrace",
        "",
        "| SLO ID | Value |",
        "|---|---:|",
    ]

    for slo_id, value in slo_values.items():
        lines.append(f"| {slo_id} | {value:.2f}% |")

    lines.extend(
        [
            "",
            "## Dynatrace Metric Keys",
            "",
            "| Metric | Purpose |",
            "|---|---|",
            "| `asr.ai.slo.value` | Main SLO percentage metric, filtered by `slo_id` |",
            "| `asr.ai.slo.predict.p95_ms` | Prediction p95 latency in milliseconds |",
            "| `asr.ai.slo.endpoint.success` | Per-endpoint success percentage |",
            "| `asr.ai.slo.endpoint.latency_ms` | Per-endpoint latency in milliseconds |",
            "",
        ]
    )

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print(f"Dynatrace SLO catalog ingest success: {ingest_success}")
    print(f"Dynatrace ingest HTTP status: {status_code}")
    print(f"Overall AI reliability score: {overall_ai_reliability_score:.2f}%")
    print(f"Summary: {SUMMARY_MD}")
    print(f"JSON report: {JSON_REPORT}")
    print(f"Metric lines: {METRIC_LINES_FILE}")

    if not ingest_success:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
