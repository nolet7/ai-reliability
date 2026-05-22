#!/usr/bin/env python3
"""
Phase 14 - Dynatrace Executive SLO Dashboard Automation

Purpose:
  Generate a Dynatrace executive dashboard-as-code pack for the
  AS AI Reliability POC SLO catalog.

This does not depend on manual dashboard creation.

It generates:
  - dashboard JSON definition
  - tile catalog
  - metric selectors
  - DQL notebook queries
  - dashboard import guidance
  - API capability evidence

Why this approach:
  Dynatrace tenants can vary by generation and enabled apps.
  Some tenants expose dashboard/configuration write APIs; others only expose
  metric ingestion and UI-based dashboard creation. This script keeps the
  dashboard-as-code pack version-controlled and attempts capability checks
  without breaking the POC if write APIs are unavailable.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/dynatrace-dashboard-automation"))
RAW_DIR = REPORT_ROOT / "raw"

OUTPUT_DIR = Path("dynatrace/dashboards")
DASHBOARD_JSON = OUTPUT_DIR / "as-ai-reliability-slo-command-center.json"
TILE_CATALOG_JSON = OUTPUT_DIR / "as-ai-reliability-dashboard-tiles.json"
METRIC_SELECTORS_MD = OUTPUT_DIR / "as-ai-reliability-metric-selectors.md"
DQL_QUERIES_MD = OUTPUT_DIR / "as-ai-reliability-dql-notebook-queries.md"
IMPORT_GUIDE_MD = OUTPUT_DIR / "as-ai-reliability-dashboard-import-guide.md"

SUMMARY_MD = REPORT_ROOT / "dynatrace-dashboard-automation-summary.md"
JSON_REPORT = REPORT_ROOT / "dynatrace-dashboard-automation-report.json"

REPORT_ROOT.mkdir(parents=True, exist_ok=True)
RAW_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

APP_NAME = env("APP_NAME", "as-ai-quality-service")
SERVICE_NAME = env("SERVICE_NAME", APP_NAME)
ENVIRONMENT = env("ENVIRONMENT", "poc")
EXPECTED_MODEL_VERSION = env("EXPECTED_MODEL_VERSION", "v1.0.3")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://139.144.255.92")

DYNATRACE_ENABLE_DASHBOARD_API_PROBE = env(
    "DYNATRACE_ENABLE_DASHBOARD_API_PROBE",
    "true",
).lower() in {"true", "1", "yes"}


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=False), encoding="utf-8")


def dt_request(method: str, path: str, payload: Dict[str, Any] | None = None) -> Tuple[int, Any]:
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
                return response.getcode(), json.loads(raw) if raw else {}
            except Exception:
                return response.getcode(), raw

    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            return exc.code, json.loads(raw) if raw else {}
        except Exception:
            return exc.code, raw

    except Exception as exc:
        return 0, str(exc)


def slo_catalog() -> List[Dict[str, Any]]:
    return [
        {
            "id": "runtime_availability",
            "name": "Runtime Availability",
            "target": 99.5,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","runtime_availability")):avg',
        },
        {
            "id": "model_health_readiness",
            "name": "Model Health Readiness",
            "target": 99.5,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","model_health_readiness")):avg',
        },
        {
            "id": "model_version_compliance",
            "name": "Model Version Compliance",
            "target": 100.0,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","model_version_compliance")):avg',
        },
        {
            "id": "prediction_success_rate",
            "name": "Prediction Success Rate",
            "target": 99.0,
            "warning": 98.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","prediction_success_rate")):avg',
        },
        {
            "id": "prediction_latency_compliance",
            "name": "Prediction Latency Compliance",
            "target": 95.0,
            "warning": 90.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","prediction_latency_compliance")):avg',
        },
        {
            "id": "canary_route_readiness",
            "name": "Canary / Rollback Readiness",
            "target": 100.0,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","canary_route_readiness")):avg',
        },
        {
            "id": "incident_automation_readiness",
            "name": "ServiceNow Incident Automation",
            "target": 100.0,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","incident_automation_readiness")):avg',
        },
        {
            "id": "observability_readiness",
            "name": "Dynatrace Observability Readiness",
            "target": 100.0,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","observability_readiness")):avg',
        },
        {
            "id": "evidence_pack_readiness",
            "name": "Evidence Pack Readiness",
            "target": 100.0,
            "warning": 99.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","evidence_pack_readiness")):avg',
        },
        {
            "id": "overall_ai_reliability_score",
            "name": "Overall AI Reliability Score",
            "target": 99.0,
            "warning": 95.0,
            "selector": 'asr.ai.slo.value:filter(eq("slo_id","overall_ai_reliability_score")):avg',
        },
    ]


def generate_tiles(catalog: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    tiles: List[Dict[str, Any]] = [
        {
            "title": "Overall AI Reliability Score",
            "type": "single_value",
            "metric": 'asr.ai.slo.value:filter(eq("slo_id","overall_ai_reliability_score")):avg',
            "unit": "percent",
            "target": 99.0,
            "warning": 95.0,
            "description": "Composite reliability score across all AS AI reliability controls.",
        },
        {
            "title": "All SLO Values by SLO ID",
            "type": "table_or_line_chart",
            "metric": 'asr.ai.slo.value:splitBy("slo_id"):avg',
            "split_by": ["slo_id"],
            "unit": "percent",
            "description": "Shows all SLO catalog values published by GitHub Actions.",
        },
        {
            "title": "Prediction p95 Latency",
            "type": "line_chart",
            "metric": "asr.ai.slo.predict.p95_ms:avg",
            "unit": "millisecond",
            "description": "Tracks measured p95 latency for the /predict endpoint.",
        },
        {
            "title": "Prediction Sample Count",
            "type": "single_value",
            "metric": "asr.ai.slo.predict.sample_count:avg",
            "unit": "count",
            "description": "Number of prediction samples used for SLO measurement.",
        },
        {
            "title": "Endpoint Success by Endpoint",
            "type": "table_or_line_chart",
            "metric": 'asr.ai.slo.endpoint.success:splitBy("endpoint"):avg',
            "split_by": ["endpoint"],
            "unit": "percent",
            "description": "Success percentage by runtime endpoint.",
        },
        {
            "title": "Endpoint Latency by Endpoint",
            "type": "line_chart",
            "metric": 'asr.ai.slo.endpoint.latency_ms:splitBy("endpoint"):avg',
            "split_by": ["endpoint"],
            "unit": "millisecond",
            "description": "Endpoint latency for /version, /health/model, /predict, and readiness endpoints.",
        },
        {
            "title": "Model Version Match",
            "type": "single_value",
            "metric": "asr.ai.slo.model.version_match:avg",
            "unit": "percent",
            "description": f"Confirms runtime model version matches {EXPECTED_MODEL_VERSION}.",
        },
    ]

    for slo in catalog:
        tiles.append(
            {
                "title": f"SLO - {slo['name']}",
                "type": "single_value",
                "metric": slo["selector"],
                "unit": "percent",
                "target": slo["target"],
                "warning": slo["warning"],
                "slo_id": slo["id"],
                "description": f"Automated SLO tile for {slo['name']}.",
            }
        )

    return tiles


def generate_dashboard(catalog: List[Dict[str, Any]], tiles: List[Dict[str, Any]]) -> Dict[str, Any]:
    return {
        "name": "AS AI Reliability SLO Command Center",
        "description": "Executive Dynatrace dashboard definition for AS AI Reliability POC SLO catalog.",
        "generated_utc": now_utc(),
        "owner": "sre-platform-team",
        "application": APP_NAME,
        "service": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "expected_model_version": EXPECTED_MODEL_VERSION,
        "public_base_url": PUBLIC_BASE_URL,
        "metrics": [
            "asr.ai.slo.value",
            "asr.ai.slo.predict.p95_ms",
            "asr.ai.slo.predict.sample_count",
            "asr.ai.slo.endpoint.success",
            "asr.ai.slo.endpoint.latency_ms",
            "asr.ai.slo.model.version_match",
        ],
        "slos": catalog,
        "tiles": tiles,
    }


def write_metric_selectors(catalog: List[Dict[str, Any]]) -> None:
    lines = [
        "# AS AI Reliability Dynatrace Metric Selectors",
        "",
        "Use these selectors when building Dynatrace dashboard tiles, SLOs, or notebook sections.",
        "",
        "## Main SLO metric",
        "",
        "```text",
        'asr.ai.slo.value:splitBy("slo_id"):avg',
        "```",
        "",
        "## Per-SLO selectors",
        "",
        "| SLO | Selector |",
        "|---|---|",
    ]

    for slo in catalog:
        lines.append(f"| {slo['name']} | `{slo['selector']}` |")

    lines.extend(
        [
            "",
            "## Supporting metrics",
            "",
            "```text",
            "asr.ai.slo.predict.p95_ms:avg",
            "asr.ai.slo.predict.sample_count:avg",
            'asr.ai.slo.endpoint.success:splitBy("endpoint"):avg',
            'asr.ai.slo.endpoint.latency_ms:splitBy("endpoint"):avg',
            "asr.ai.slo.model.version_match:avg",
            "```",
        ]
    )

    METRIC_SELECTORS_MD.write_text("\n".join(lines), encoding="utf-8")


def write_dql_queries() -> None:
    lines = [
        "# AS AI Reliability DQL Notebook Queries",
        "",
        "Use these in Dynatrace Notebooks if your tenant supports DQL metric queries.",
        "",
        "## All SLO values",
        "",
        "```text",
        "timeseries avg(asr.ai.slo.value), by:{slo_id}, from: now()-2h",
        "```",
        "",
        "## Overall AI reliability score",
        "",
        "```text",
        'timeseries avg(asr.ai.slo.value), filter: {slo_id == "overall_ai_reliability_score"}, from: now()-2h',
        "```",
        "",
        "## Prediction p95 latency",
        "",
        "```text",
        "timeseries avg(asr.ai.slo.predict.p95_ms), from: now()-2h",
        "```",
        "",
        "## Endpoint success by endpoint",
        "",
        "```text",
        "timeseries avg(asr.ai.slo.endpoint.success), by:{endpoint}, from: now()-2h",
        "```",
        "",
        "## Endpoint latency by endpoint",
        "",
        "```text",
        "timeseries avg(asr.ai.slo.endpoint.latency_ms), by:{endpoint}, from: now()-2h",
        "```",
    ]

    DQL_QUERIES_MD.write_text("\n".join(lines), encoding="utf-8")


def write_import_guide() -> None:
    lines = [
        "# AS AI Reliability Dynatrace Dashboard Import Guide",
        "",
        "This dashboard pack is generated automatically by GitHub Actions.",
        "",
        "## Generated dashboard files",
        "",
        f"- `{DASHBOARD_JSON}`",
        f"- `{TILE_CATALOG_JSON}`",
        f"- `{METRIC_SELECTORS_MD}`",
        f"- `{DQL_QUERIES_MD}`",
        "",
        "## Dashboard goal",
        "",
        "The dashboard provides an executive command center for AI reliability:",
        "",
        "- Overall AI reliability score",
        "- Runtime availability",
        "- Model health readiness",
        "- Model version compliance",
        "- Prediction success rate",
        "- Prediction latency compliance",
        "- Canary and rollback readiness",
        "- ServiceNow incident automation readiness",
        "- Dynatrace observability readiness",
        "- Evidence pack readiness",
        "",
        "## Metric source",
        "",
        "The dashboard uses metrics already published to Dynatrace by workflow:",
        "",
        "```text",
        "10 - Dynatrace SLO Catalog Metrics",
        "```",
        "",
        "## Custom metrics",
        "",
        "```text",
        "asr.ai.slo.value",
        "asr.ai.slo.predict.p95_ms",
        "asr.ai.slo.predict.sample_count",
        "asr.ai.slo.endpoint.success",
        "asr.ai.slo.endpoint.latency_ms",
        "asr.ai.slo.model.version_match",
        "```",
    ]

    IMPORT_GUIDE_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    started = now_utc()

    catalog = slo_catalog()
    tiles = generate_tiles(catalog)
    dashboard = generate_dashboard(catalog, tiles)

    write_json(DASHBOARD_JSON, dashboard)
    write_json(TILE_CATALOG_JSON, {"tiles": tiles})
    write_metric_selectors(catalog)
    write_dql_queries()
    write_import_guide()

    api_results: Dict[str, Any] = {}

    if DYNATRACE_ENABLE_DASHBOARD_API_PROBE:
        checks = {
            "settings_schemas": "/api/v2/settings/schemas",
            "metrics_descriptor_probe": "/api/v2/metrics?metricSelector=asr.ai.slo.value",
        }

        for name, path in checks.items():
            status, body = dt_request("GET", path)
            api_results[name] = {
                "http_status": status,
                "response": body,
            }
            write_json(RAW_DIR / f"{name}.json", api_results[name])

    report = {
        "phase": "Phase 14 - Dynatrace Executive SLO Dashboard Automation",
        "started_utc": started,
        "app_name": APP_NAME,
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "dashboard_name": dashboard["name"],
        "tile_count": len(tiles),
        "slo_count": len(catalog),
        "api_probe_enabled": DYNATRACE_ENABLE_DASHBOARD_API_PROBE,
        "api_results": api_results,
        "outputs": {
            "dashboard_json": str(DASHBOARD_JSON),
            "tile_catalog_json": str(TILE_CATALOG_JSON),
            "metric_selectors_md": str(METRIC_SELECTORS_MD),
            "dql_queries_md": str(DQL_QUERIES_MD),
            "import_guide_md": str(IMPORT_GUIDE_MD),
        },
    }

    write_json(JSON_REPORT, report)

    lines = [
        "# Dynatrace Executive SLO Dashboard Automation Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| Dashboard | {dashboard['name']} |",
        f"| SLO Count | {len(catalog)} |",
        f"| Tile Count | {len(tiles)} |",
        f"| API Probe Enabled | {DYNATRACE_ENABLE_DASHBOARD_API_PROBE} |",
        "",
        "## Generated Dashboard-as-Code Files",
        "",
        "| File | Purpose |",
        "|---|---|",
        f"| `{DASHBOARD_JSON}` | Main executive dashboard definition |",
        f"| `{TILE_CATALOG_JSON}` | Tile catalog with metric selectors |",
        f"| `{METRIC_SELECTORS_MD}` | Human-readable metric selector reference |",
        f"| `{DQL_QUERIES_MD}` | Notebook/DQL query pack |",
        f"| `{IMPORT_GUIDE_MD}` | Dashboard import and usage guide |",
        "",
        "## Dashboard Tiles",
        "",
        "| Tile | Metric | Type |",
        "|---|---|---|",
    ]

    for tile in tiles:
        lines.append(f"| {tile['title']} | `{tile['metric']}` | {tile['type']} |")

    lines.extend(
        [
            "",
            "## API Capability Probe",
            "",
            "| Check | HTTP Status | Meaning |",
            "|---|---:|---|",
        ]
    )

    if not api_results:
        lines.append("| skipped | n/a | API probe disabled |")
    else:
        for name, result in api_results.items():
            status = int(result["http_status"]) if str(result["http_status"]).isdigit() else 0
            if 200 <= status < 300:
                meaning = "API access available"
            elif status == 403:
                meaning = "Token lacks read/configuration scope"
            elif status == 404:
                meaning = "Endpoint unavailable for this tenant or wrong API path"
            else:
                meaning = "Review raw API response"
            lines.append(f"| {name} | {status} | {meaning} |")

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print("Dynatrace executive dashboard automation completed.")
    print(f"Dashboard definition: {DASHBOARD_JSON}")
    print(f"Summary: {SUMMARY_MD}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
