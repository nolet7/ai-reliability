#!/usr/bin/env python3
"""
Phase 15 - SLO Breach Simulation + End-to-End Incident Proof

Purpose:
  Simulate an enterprise SLO breach for the AS AI Reliability POC.

This script:
  1. Publishes degraded SLO values to Dynatrace.
  2. Publishes a Dynatrace custom alert event.
  3. Captures evidence files.
  4. Optionally exits with failure so GitHub Actions triggers ServiceNow incident automation.

Why this matters:
  A strong SRE demo must prove both the healthy path and the failure path:
    - Detection
    - Evidence
    - Alert/event
    - Incident creation/update
    - Triage context
    - Recovery action
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/slo-breach-simulation"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "slo-breach-simulation-summary.md"
JSON_REPORT = REPORT_ROOT / "slo-breach-simulation-report.json"
METRIC_LINES_FILE = REPORT_ROOT / "slo-breach-metric-lines.txt"

RAW_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

APP_NAME = env("APP_NAME", "as-ai-quality-service")
SERVICE_NAME = env("SERVICE_NAME", APP_NAME)
ENVIRONMENT = env("ENVIRONMENT", "poc")
EXPECTED_MODEL_VERSION = env("EXPECTED_MODEL_VERSION", "v1.0.3")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://139.144.255.92")

BREACH_SCENARIO = env("BREACH_SCENARIO", "model_version_and_latency")
FAIL_WORKFLOW_FOR_INCIDENT = env("FAIL_WORKFLOW_FOR_INCIDENT", "true").lower() in {"true", "1", "yes"}

GITHUB_SERVER_URL = env("GITHUB_SERVER_URL", "https://github.com")
GITHUB_REPOSITORY = env("GITHUB_REPOSITORY", "nolet7/ai-reliability")
GITHUB_RUN_ID = env("GITHUB_RUN_ID", "")
GITHUB_RUN_URL = (
    f"{GITHUB_SERVER_URL}/{GITHUB_REPOSITORY}/actions/runs/{GITHUB_RUN_ID}"
    if GITHUB_RUN_ID
    else ""
)


def now_ms() -> int:
    return int(time.time() * 1000)


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def safe_dim(value: str) -> str:
    value = str(value)
    for bad in [",", "=", " ", "\n", "\r", "\t"]:
        value = value.replace(bad, "_")
    return value


def metric_line(metric: str, value: float, slo_id: str, extra_dims: Dict[str, str] | None = None) -> str:
    dims = {
        "app": APP_NAME,
        "service": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "slo_id": slo_id,
        "scenario": BREACH_SCENARIO,
    }

    if extra_dims:
        dims.update(extra_dims)

    dim_text = ",".join(f"{safe_dim(k)}={safe_dim(v)}" for k, v in dims.items())
    return f"{metric},{dim_text} gauge,{float(value):.4f} {now_ms()}"


def post_text(path: str, body: str) -> Tuple[int, str]:
    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN missing"

    request = urllib.request.Request(
        url=f"{DYNATRACE_ENV_URL}{path}",
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Api-Token {DYNATRACE_API_TOKEN}",
            "Content-Type": "text/plain; charset=utf-8",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return response.getcode(), response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except Exception as exc:
        return 0, str(exc)


def post_json(path: str, payload: Dict[str, Any]) -> Tuple[int, str]:
    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN missing"

    request = urllib.request.Request(
        url=f"{DYNATRACE_ENV_URL}{path}",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Api-Token {DYNATRACE_API_TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return response.getcode(), response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except Exception as exc:
        return 0, str(exc)


def build_breach_values() -> Dict[str, float]:
    """
    Healthy Phase 11 published 100% SLO values.
    This intentionally publishes degraded values to prove detection/incident flow.
    """

    if BREACH_SCENARIO == "latency":
        return {
            "runtime_availability": 100.0,
            "model_health_readiness": 100.0,
            "model_version_compliance": 100.0,
            "prediction_success_rate": 100.0,
            "prediction_latency_compliance": 40.0,
            "canary_route_readiness": 100.0,
            "incident_automation_readiness": 100.0,
            "observability_readiness": 100.0,
            "evidence_pack_readiness": 100.0,
            "overall_ai_reliability_score": 94.0,
        }

    if BREACH_SCENARIO == "model_version":
        return {
            "runtime_availability": 100.0,
            "model_health_readiness": 100.0,
            "model_version_compliance": 0.0,
            "prediction_success_rate": 100.0,
            "prediction_latency_compliance": 100.0,
            "canary_route_readiness": 0.0,
            "incident_automation_readiness": 100.0,
            "observability_readiness": 100.0,
            "evidence_pack_readiness": 100.0,
            "overall_ai_reliability_score": 80.0,
        }

    if BREACH_SCENARIO == "availability":
        return {
            "runtime_availability": 60.0,
            "model_health_readiness": 60.0,
            "model_version_compliance": 100.0,
            "prediction_success_rate": 50.0,
            "prediction_latency_compliance": 50.0,
            "canary_route_readiness": 70.0,
            "incident_automation_readiness": 100.0,
            "observability_readiness": 100.0,
            "evidence_pack_readiness": 100.0,
            "overall_ai_reliability_score": 70.0,
        }

    return {
        "runtime_availability": 100.0,
        "model_health_readiness": 100.0,
        "model_version_compliance": 0.0,
        "prediction_success_rate": 98.0,
        "prediction_latency_compliance": 40.0,
        "canary_route_readiness": 0.0,
        "incident_automation_readiness": 100.0,
        "observability_readiness": 100.0,
        "evidence_pack_readiness": 100.0,
        "overall_ai_reliability_score": 75.0,
    }


def build_event_payload(breach_values: Dict[str, float]) -> Dict[str, Any]:
    breached = {
        key: value
        for key, value in breach_values.items()
        if (
            (key == "overall_ai_reliability_score" and value < 99.0)
            or (key == "runtime_availability" and value < 99.5)
            or (key == "model_health_readiness" and value < 99.5)
            or (key == "model_version_compliance" and value < 100.0)
            or (key == "prediction_success_rate" and value < 99.0)
            or (key == "prediction_latency_compliance" and value < 95.0)
            or (key == "canary_route_readiness" and value < 100.0)
        )
    }

    return {
        "eventType": "CUSTOM_ALERT",
        "title": "AS AI Reliability SLO breach simulation",
        "description": (
            "Intentional SLO breach simulation for AS AI Reliability POC. "
            "This validates Dynatrace SLO eventing, GitHub Actions evidence, "
            "and ServiceNow incident-on-failure automation."
        ),
        "properties": {
            "app": APP_NAME,
            "service": SERVICE_NAME,
            "environment": ENVIRONMENT,
            "scenario": BREACH_SCENARIO,
            "expected_model_version": EXPECTED_MODEL_VERSION,
            "public_base_url": PUBLIC_BASE_URL,
            "github_run_url": GITHUB_RUN_URL,
            "breached_slos": json.dumps(breached),
            "automation_phase": "Phase 15",
            "timestamp_utc": now_utc(),
        },
    }


def main() -> int:
    started_utc = now_utc()
    breach_values = build_breach_values()

    metric_lines: List[str] = []

    for slo_id, value in breach_values.items():
        metric_lines.append(metric_line("asr.ai.slo.value", value, slo_id))

    metric_lines.append(
        metric_line(
            "asr.ai.slo.predict.p95_ms",
            2500.0 if "latency" in BREACH_SCENARIO else 45.0,
            "prediction_latency_p95",
        )
    )

    metric_lines.append(
        metric_line(
            "asr.ai.slo.model.version_match",
            breach_values.get("model_version_compliance", 100.0),
            "model_version_match",
        )
    )

    METRIC_LINES_FILE.write_text("\n".join(metric_lines) + "\n", encoding="utf-8")

    metric_status, metric_response = post_text(
        "/api/v2/metrics/ingest",
        "\n".join(metric_lines) + "\n",
    )

    (RAW_DIR / "dynatrace_breach_metric_response.txt").write_text(
        f"HTTP_STATUS={metric_status}\n{metric_response}\n",
        encoding="utf-8",
    )

    event_payload = build_event_payload(breach_values)
    (RAW_DIR / "dynatrace_breach_event_payload.json").write_text(
        json.dumps(event_payload, indent=2),
        encoding="utf-8",
    )

    event_status, event_response = post_json("/api/v2/events/ingest", event_payload)

    (RAW_DIR / "dynatrace_breach_event_response.txt").write_text(
        f"HTTP_STATUS={event_status}\n{event_response}\n",
        encoding="utf-8",
    )

    metric_success = 200 <= metric_status < 300
    event_success = 200 <= event_status < 300

    final_status = "breach_simulated" if metric_success else "breach_metric_failed"

    result = {
        "phase": "Phase 15 - SLO Breach Simulation and Incident Proof",
        "started_utc": started_utc,
        "app_name": APP_NAME,
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "scenario": BREACH_SCENARIO,
        "public_base_url": PUBLIC_BASE_URL,
        "expected_model_version": EXPECTED_MODEL_VERSION,
        "github_run_url": GITHUB_RUN_URL,
        "breach_values": breach_values,
        "dynatrace_metric_http_status": metric_status,
        "dynatrace_metric_success": metric_success,
        "dynatrace_event_http_status": event_status,
        "dynatrace_event_success": event_success,
        "fail_workflow_for_incident": FAIL_WORKFLOW_FOR_INCIDENT,
        "final_status": final_status,
    }

    JSON_REPORT.write_text(json.dumps(result, indent=2), encoding="utf-8")

    lines = [
        "# AS AI Reliability SLO Breach Simulation Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| Scenario | {BREACH_SCENARIO} |",
        f"| Public Base URL | {PUBLIC_BASE_URL} |",
        f"| Expected Model Version | {EXPECTED_MODEL_VERSION} |",
        f"| GitHub Run URL | {GITHUB_RUN_URL} |",
        f"| Dynatrace Metric HTTP Status | {metric_status} |",
        f"| Dynatrace Metric Success | {metric_success} |",
        f"| Dynatrace Event HTTP Status | {event_status} |",
        f"| Dynatrace Event Success | {event_success} |",
        f"| Fail Workflow For Incident | {FAIL_WORKFLOW_FOR_INCIDENT} |",
        "",
        "## Simulated SLO Values",
        "",
        "| SLO ID | Simulated Value |",
        "|---|---:|",
    ]

    for slo_id, value in breach_values.items():
        lines.append(f"| {slo_id} | {value:.2f}% |")

    lines.extend(
        [
            "",
            "## Expected Operational Chain",
            "",
            "1. Dynatrace receives degraded SLO metric values.",
            "2. Dynatrace receives a custom alert event if event-ingest permission is available.",
            "3. This GitHub workflow intentionally fails when `FAIL_WORKFLOW_FOR_INCIDENT=true`.",
            "4. ServiceNow incident-on-failure workflow creates or updates an incident.",
            "5. SRE reviews GitHub artifact, Dynatrace event, and ServiceNow incident.",
            "",
            "## Evidence Files",
            "",
            "- `slo-breach-simulation-summary.md`",
            "- `slo-breach-simulation-report.json`",
            "- `slo-breach-metric-lines.txt`",
            "- `raw/dynatrace_breach_metric_response.txt`",
            "- `raw/dynatrace_breach_event_payload.json`",
            "- `raw/dynatrace_breach_event_response.txt`",
        ]
    )

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print(f"SLO breach simulation final status: {final_status}")
    print(f"Dynatrace metric status: {metric_status}")
    print(f"Dynatrace event status: {event_status}")
    print(f"Fail workflow for incident: {FAIL_WORKFLOW_FOR_INCIDENT}")
    print(f"Summary: {SUMMARY_MD}")

    if not metric_success:
        return 1

    if FAIL_WORKFLOW_FOR_INCIDENT:
        print("Intentional failure enabled to trigger ServiceNow incident-on-failure automation.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
