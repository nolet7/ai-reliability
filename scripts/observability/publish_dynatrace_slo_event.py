#!/usr/bin/env python3
"""
Phase 12 - Dynatrace SLO Event Publisher

Purpose:
  Create a Dynatrace custom event when AS AI Reliability SLOs breach target.

Why:
  Metrics show the SLO values.
  Events/problems create operational visibility and alert-style evidence.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/dynatrace-slo-events"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "dynatrace-slo-event-summary.md"
JSON_REPORT = REPORT_ROOT / "dynatrace-slo-event-report.json"

RAW_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

APP_NAME = env("APP_NAME", "as-ai-quality-service")
SERVICE_NAME = env("SERVICE_NAME", APP_NAME)
ENVIRONMENT = env("ENVIRONMENT", "poc")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://139.144.255.92")
EXPECTED_MODEL_VERSION = env("EXPECTED_MODEL_VERSION", "v1.0.3")

FORCE_EVENT_TEST = env("FORCE_EVENT_TEST", "false").lower() in {"true", "1", "yes"}

SLO_REPORT_PATH = Path(
    env(
        "SLO_REPORT_PATH",
        "reports/dynatrace-slo-catalog/dynatrace-slo-catalog-report.json",
    )
)


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_slo_report() -> dict:
    if not SLO_REPORT_PATH.exists():
        return {}

    try:
        return json.loads(SLO_REPORT_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def determine_breaches(report: dict) -> list:
    slo_values = report.get("slo_values", {})

    checks = [
        ("runtime_availability", 99.5),
        ("model_health_readiness", 99.5),
        ("model_version_compliance", 100.0),
        ("prediction_success_rate", 99.0),
        ("prediction_latency_compliance", 95.0),
        ("canary_route_readiness", 100.0),
        ("incident_automation_readiness", 100.0),
        ("observability_readiness", 100.0),
        ("evidence_pack_readiness", 100.0),
        ("overall_ai_reliability_score", 99.0),
    ]

    breaches = []

    for slo_id, target in checks:
        value = float(slo_values.get(slo_id, 0.0))
        if value < target:
            breaches.append(
                {
                    "slo_id": slo_id,
                    "value": value,
                    "target": target,
                }
            )

    return breaches


def post_dynatrace_event(payload: dict) -> tuple[int, str]:
    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN is missing"

    url = f"{DYNATRACE_ENV_URL}/api/v2/events/ingest"

    request = urllib.request.Request(
        url=url,
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
            body = response.read().decode("utf-8", errors="replace")
            return response.getcode(), body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body
    except Exception as exc:
        return 0, str(exc)


def main() -> int:
    started = now_utc()
    report = load_slo_report()
    breaches = determine_breaches(report)

    should_send_event = FORCE_EVENT_TEST or bool(breaches)

    event_payload = {
        "eventType": "CUSTOM_ALERT",
        "title": "AS AI Reliability SLO breach detected",
        "description": (
            "AS AI Reliability POC SLO catalog detected one or more SLO breaches. "
            "Review Dynatrace SLO metrics, GitHub Actions evidence, Kubernetes runtime, "
            "model version, prediction success, and ServiceNow incident automation."
        ),
        "properties": {
            "app": APP_NAME,
            "service": SERVICE_NAME,
            "environment": ENVIRONMENT,
            "public_base_url": PUBLIC_BASE_URL,
            "expected_model_version": EXPECTED_MODEL_VERSION,
            "generated_utc": started,
            "force_event_test": str(FORCE_EVENT_TEST),
            "breach_count": str(len(breaches)),
            "breaches": json.dumps(breaches),
        },
    }

    status_code = 0
    response_body = "No event sent because no SLO breach was detected."

    if should_send_event:
        status_code, response_body = post_dynatrace_event(event_payload)

    (RAW_DIR / "dynatrace_event_payload.json").write_text(
        json.dumps(event_payload, indent=2),
        encoding="utf-8",
    )

    (RAW_DIR / "dynatrace_event_response.txt").write_text(
        f"HTTP_STATUS={status_code}\n{response_body}\n",
        encoding="utf-8",
    )

    success = (not should_send_event) or (200 <= status_code < 300)

    result = {
        "phase": "Phase 12 - Dynatrace SLO Event Publisher",
        "started_utc": started,
        "app_name": APP_NAME,
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "force_event_test": FORCE_EVENT_TEST,
        "breaches": breaches,
        "should_send_event": should_send_event,
        "dynatrace_event_http_status": status_code,
        "success": success,
    }

    JSON_REPORT.write_text(json.dumps(result, indent=2), encoding="utf-8")

    lines = [
        "# Dynatrace SLO Event Trigger Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| Force Event Test | {FORCE_EVENT_TEST} |",
        f"| SLO Breach Count | {len(breaches)} |",
        f"| Should Send Event | {should_send_event} |",
        f"| Dynatrace Event HTTP Status | {status_code} |",
        f"| Success | {success} |",
        "",
        "## Breaches",
        "",
        "| SLO ID | Value | Target |",
        "|---|---:|---:|",
    ]

    if breaches:
        for b in breaches:
            lines.append(f"| {b['slo_id']} | {b['value']:.2f}% | {b['target']:.2f}% |")
    else:
        lines.append("| none | 100.00% | target met |")

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print(f"Dynatrace event trigger success: {success}")
    print(f"Should send event: {should_send_event}")
    print(f"Dynatrace event HTTP status: {status_code}")
    print(f"Summary: {SUMMARY_MD}")

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
