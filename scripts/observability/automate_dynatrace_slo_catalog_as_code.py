#!/usr/bin/env python3
"""
Phase 13 - Dynatrace SLO Catalog Automation as Code

Purpose:
  Automate Dynatrace SLO catalog setup for the AS AI Reliability POC.

This automation:
  1. Defines the SLO catalog as code.
  2. Generates Dynatrace metric selector expressions.
  3. Generates Dynatrace SLO/dashboard/event definitions.
  4. Attempts API-based creation where token permissions allow it.
  5. Produces enterprise evidence artifacts.

Important:
  Dynatrace accepted custom metrics with HTTP 202 in Phase 11.
  This script builds the automation layer on top of those custom metrics.
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


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/dynatrace-slo-as-code"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "dynatrace-slo-as-code-summary.md"
JSON_REPORT = REPORT_ROOT / "dynatrace-slo-as-code-report.json"

CATALOG_DIR = Path("dynatrace/slo-as-code")
SLO_CATALOG_JSON = CATALOG_DIR / "as-ai-dynatrace-slo-catalog.json"
DASHBOARD_DEFINITION_JSON = CATALOG_DIR / "as-ai-dynatrace-dashboard-definition.json"
EVENT_RULES_JSON = CATALOG_DIR / "as-ai-dynatrace-slo-event-rules.json"
SLO_DEFINITIONS_JSON = CATALOG_DIR / "as-ai-dynatrace-slo-definitions.json"

REPORT_ROOT.mkdir(parents=True, exist_ok=True)
RAW_DIR.mkdir(parents=True, exist_ok=True)
CATALOG_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

APP_NAME = env("APP_NAME", "as-ai-quality-service")
SERVICE_NAME = env("SERVICE_NAME", APP_NAME)
ENVIRONMENT = env("ENVIRONMENT", "poc")
EXPECTED_MODEL_VERSION = env("EXPECTED_MODEL_VERSION", "v1.0.3")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://139.144.255.92")

ENABLE_API_CREATE = env("DYNATRACE_ENABLE_API_CREATE", "true").lower() in {
    "true",
    "1",
    "yes",
}

ENABLE_TEST_EVENT = env("DYNATRACE_ENABLE_TEST_EVENT", "true").lower() in {
    "true",
    "1",
    "yes",
}


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=False), encoding="utf-8")


def dt_request(method: str, path: str, payload: Dict[str, Any] | None = None) -> Tuple[int, Dict[str, Any] | str]:
    """
    Generic Dynatrace API request helper.

    This script uses API calls opportunistically:
    - If token scope allows creation, the call succeeds.
    - If token lacks scope, the error is captured in evidence artifacts.
    """

    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN missing"

    url = f"{DYNATRACE_ENV_URL}{path}"
    body = None

    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url=url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Api-Token {DYNATRACE_API_TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            raw = response.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = raw
            return response.getcode(), parsed

    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except Exception:
            parsed = raw
        return exc.code, parsed

    except Exception as exc:
        return 0, str(exc)


def slo_catalog() -> List[Dict[str, Any]]:
    return [
        {
            "id": "runtime_availability",
            "name": "AS AI Runtime Availability",
            "target": 99.5,
            "warning": 99.0,
            "description": "Measures /health/live, /health/ready, and /version success.",
        },
        {
            "id": "model_health_readiness",
            "name": "AS AI Model Health Readiness",
            "target": 99.5,
            "warning": 99.0,
            "description": "Measures /health/model readiness.",
        },
        {
            "id": "model_version_compliance",
            "name": "AS AI Model Version Compliance",
            "target": 100.0,
            "warning": 99.0,
            "description": "Confirms runtime endpoints return the approved model version.",
        },
        {
            "id": "prediction_success_rate",
            "name": "AS AI Prediction Success Rate",
            "target": 99.0,
            "warning": 98.0,
            "description": "Measures successful /predict responses.",
        },
        {
            "id": "prediction_latency_compliance",
            "name": "AS AI Prediction Latency Compliance",
            "target": 95.0,
            "warning": 90.0,
            "description": "Measures percentage of prediction requests under latency threshold.",
        },
        {
            "id": "canary_route_readiness",
            "name": "AS AI Canary Route Readiness",
            "target": 100.0,
            "warning": 99.0,
            "description": "Confirms public route returns the expected model version after canary or rollback.",
        },
        {
            "id": "incident_automation_readiness",
            "name": "AS AI ServiceNow Incident Automation Readiness",
            "target": 100.0,
            "warning": 99.0,
            "description": "Confirms ServiceNow incident automation workflow and script exist.",
        },
        {
            "id": "observability_readiness",
            "name": "AS AI Dynatrace Observability Readiness",
            "target": 100.0,
            "warning": 99.0,
            "description": "Confirms Dynatrace metric ingestion is configured and healthy.",
        },
        {
            "id": "evidence_pack_readiness",
            "name": "AS AI Evidence Pack Readiness",
            "target": 100.0,
            "warning": 99.0,
            "description": "Confirms enterprise evidence pack workflows exist.",
        },
        {
            "id": "overall_ai_reliability_score",
            "name": "AS AI Overall Reliability Score",
            "target": 99.0,
            "warning": 95.0,
            "description": "Composite score across all AI reliability SLOs.",
        },
    ]


def metric_selector(slo_id: str) -> str:
    return f'asr.ai.slo.value:filter(eq("slo_id","{slo_id}")):avg'


def generate_slo_definitions(catalog: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    definitions = []

    for slo in catalog:
        definitions.append(
            {
                "name": slo["name"],
                "enabled": True,
                "description": slo["description"],
                "metric_key": "asr.ai.slo.value",
                "metric_selector": metric_selector(slo["id"]),
                "slo_id": slo["id"],
                "target_percent": slo["target"],
                "warning_percent": slo["warning"],
                "evaluation_window": "7d",
                "dashboard_group": "AS AI Reliability",
            }
        )

    return definitions


def generate_event_rules(catalog: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    rules = []

    for slo in catalog:
        rules.append(
            {
                "name": f"{slo['name']} Breach",
                "slo_id": slo["id"],
                "metric_selector": metric_selector(slo["id"]),
                "threshold": slo["target"],
                "operator": "BELOW",
                "event_type": "CUSTOM_ALERT",
                "title": f"{slo['name']} below target",
                "description": (
                    f"{slo['name']} is below target. "
                    f"Target={slo['target']}%, Warning={slo['warning']}%, "
                    f"Application={APP_NAME}, Environment={ENVIRONMENT}."
                ),
            }
        )

    return rules


def generate_dashboard_definition(catalog: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Dashboard definition as code.

    This JSON is intentionally vendor-neutral enough to keep it readable,
    but includes the exact Dynatrace metric selectors for each tile.
    If the tenant supports dashboard API creation, the same data can be
    transformed into the tenant-specific dashboard payload.
    """

    tiles = []

    tiles.append(
        {
            "title": "AS AI Overall Reliability Score",
            "visualization": "single_value",
            "metric_selector": metric_selector("overall_ai_reliability_score"),
            "thresholds": {"target": 99.0, "warning": 95.0},
        }
    )

    tiles.append(
        {
            "title": "All SLO Values by slo_id",
            "visualization": "table_or_line_chart",
            "metric_selector": 'asr.ai.slo.value:splitBy("slo_id"):avg',
            "split_by": ["slo_id"],
        }
    )

    tiles.append(
        {
            "title": "Prediction p95 Latency",
            "visualization": "line_chart",
            "metric_selector": "asr.ai.slo.predict.p95_ms:avg",
            "unit": "ms",
        }
    )

    tiles.append(
        {
            "title": "Endpoint Success by Endpoint",
            "visualization": "table_or_line_chart",
            "metric_selector": 'asr.ai.slo.endpoint.success:splitBy("endpoint"):avg',
            "split_by": ["endpoint"],
        }
    )

    tiles.append(
        {
            "title": "Endpoint Latency by Endpoint",
            "visualization": "line_chart",
            "metric_selector": 'asr.ai.slo.endpoint.latency_ms:splitBy("endpoint"):avg',
            "split_by": ["endpoint"],
            "unit": "ms",
        }
    )

    for slo in catalog:
        tiles.append(
            {
                "title": slo["name"],
                "visualization": "single_value",
                "metric_selector": metric_selector(slo["id"]),
                "thresholds": {"target": slo["target"], "warning": slo["warning"]},
            }
        )

    return {
        "name": "AS AI Reliability SLO Command Center",
        "description": "Automated dashboard definition for AS AI Reliability POC SLO catalog.",
        "owner": "sre-platform-team",
        "environment": ENVIRONMENT,
        "app": APP_NAME,
        "tiles": tiles,
    }


def create_test_event() -> Tuple[int, Any]:
    payload = {
        "eventType": "CUSTOM_ANNOTATION",
        "title": "AS AI Reliability SLO-as-Code automation completed",
        "description": (
            "Dynatrace SLO-as-Code automation generated SLO catalog, "
            "dashboard definitions, and event rules as code."
        ),
        "properties": {
            "app": APP_NAME,
            "service": SERVICE_NAME,
            "environment": ENVIRONMENT,
            "public_base_url": PUBLIC_BASE_URL,
            "expected_model_version": EXPECTED_MODEL_VERSION,
            "automation_phase": "Phase 13",
            "generated_utc": now_utc(),
        },
    }

    return dt_request("POST", "/api/v2/events/ingest", payload)


def main() -> int:
    started = now_utc()
    catalog = slo_catalog()
    slo_definitions = generate_slo_definitions(catalog)
    event_rules = generate_event_rules(catalog)
    dashboard_definition = generate_dashboard_definition(catalog)

    catalog_payload = {
        "project": "AS AI Reliability POC",
        "app": APP_NAME,
        "service": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "expected_model_version": EXPECTED_MODEL_VERSION,
        "public_base_url": PUBLIC_BASE_URL,
        "metric_key": "asr.ai.slo.value",
        "slos": catalog,
        "generated_utc": started,
    }

    write_json(SLO_CATALOG_JSON, catalog_payload)
    write_json(SLO_DEFINITIONS_JSON, slo_definitions)
    write_json(EVENT_RULES_JSON, event_rules)
    write_json(DASHBOARD_DEFINITION_JSON, dashboard_definition)

    api_results: Dict[str, Any] = {}

    if ENABLE_TEST_EVENT:
        status, body = create_test_event()
        api_results["test_event"] = {
            "http_status": status,
            "response": body,
        }
        write_json(RAW_DIR / "dynatrace_test_event_response.json", api_results["test_event"])

    # This is a placeholder capability test for API connectivity.
    # Full dashboard/SLO creation varies by Dynatrace tenant generation.
    # We capture capability errors as evidence instead of hiding them.
    if ENABLE_API_CREATE:
        status, body = dt_request("GET", "/api/v2/settings/schemas")
        api_results["settings_schema_access"] = {
            "http_status": status,
            "response": body,
        }
        write_json(RAW_DIR / "dynatrace_settings_schema_access.json", api_results["settings_schema_access"])

    # Generate a shell helper for metric selectors.
    selectors_file = CATALOG_DIR / "as-ai-dynatrace-metric-selectors.sh"
    selector_lines = [
        "#!/usr/bin/env bash",
        "# Generated Dynatrace metric selectors for AS AI Reliability SLO catalog.",
        "",
        'export AS_AI_ALL_SLOS=\'asr.ai.slo.value:splitBy("slo_id"):avg\'',
        'export AS_AI_PREDICT_P95=\'asr.ai.slo.predict.p95_ms:avg\'',
        'export AS_AI_ENDPOINT_SUCCESS=\'asr.ai.slo.endpoint.success:splitBy("endpoint"):avg\'',
        'export AS_AI_ENDPOINT_LATENCY=\'asr.ai.slo.endpoint.latency_ms:splitBy("endpoint"):avg\'',
    ]

    for slo in catalog:
        env_name = f"AS_AI_SLO_{slo['id'].upper()}"
        selector_lines.append(f"export {env_name}='{metric_selector(slo['id'])}'")

    selectors_file.write_text("\n".join(selector_lines) + "\n", encoding="utf-8")

    report = {
        "phase": "Phase 13 - Dynatrace SLO Catalog Automation as Code",
        "started_utc": started,
        "app": APP_NAME,
        "service": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "catalog_count": len(catalog),
        "dashboard_tile_count": len(dashboard_definition["tiles"]),
        "enable_api_create": ENABLE_API_CREATE,
        "enable_test_event": ENABLE_TEST_EVENT,
        "api_results": api_results,
        "outputs": {
            "slo_catalog": str(SLO_CATALOG_JSON),
            "slo_definitions": str(SLO_DEFINITIONS_JSON),
            "event_rules": str(EVENT_RULES_JSON),
            "dashboard_definition": str(DASHBOARD_DEFINITION_JSON),
            "metric_selectors": str(selectors_file),
        },
    }

    write_json(JSON_REPORT, report)

    lines = [
        "# Dynatrace SLO Catalog Automation as Code Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| SLO Count | {len(catalog)} |",
        f"| Dashboard Tile Count | {len(dashboard_definition['tiles'])} |",
        f"| API Create Enabled | {ENABLE_API_CREATE} |",
        f"| Test Event Enabled | {ENABLE_TEST_EVENT} |",
        "",
        "## Generated Files",
        "",
        "| File | Purpose |",
        "|---|---|",
        f"| `{SLO_CATALOG_JSON}` | Version-controlled SLO catalog |",
        f"| `{SLO_DEFINITIONS_JSON}` | SLO definition payloads |",
        f"| `{EVENT_RULES_JSON}` | SLO breach event rules |",
        f"| `{DASHBOARD_DEFINITION_JSON}` | Dashboard-as-code definition |",
        f"| `{selectors_file}` | Reusable metric selectors |",
        "",
        "## SLO Catalog",
        "",
        "| SLO ID | Target | Warning | Metric Selector |",
        "|---|---:|---:|---|",
    ]

    for slo in catalog:
        lines.append(
            f"| {slo['id']} | {slo['target']} | {slo['warning']} | `{metric_selector(slo['id'])}` |"
        )

    lines.extend(
        [
            "",
            "## API Results",
            "",
            "| API Check | HTTP Status | Meaning |",
            "|---|---:|---|",
        ]
    )

    if "test_event" in api_results:
        status = api_results["test_event"]["http_status"]
        meaning = "Dynatrace event accepted" if 200 <= int(status) < 300 else "Token may need events ingest permission"
        lines.append(f"| Test event ingest | {status} | {meaning} |")

    if "settings_schema_access" in api_results:
        status = api_results["settings_schema_access"]["http_status"]
        meaning = "Settings API available" if 200 <= int(status) < 300 else "Token may need settings/configuration permissions"
        lines.append(f"| Settings schema access | {status} | {meaning} |")

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print("Dynatrace SLO-as-Code automation completed.")
    print(f"SLO catalog: {SLO_CATALOG_JSON}")
    print(f"Dashboard definition: {DASHBOARD_DEFINITION_JSON}")
    print(f"Summary: {SUMMARY_MD}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
