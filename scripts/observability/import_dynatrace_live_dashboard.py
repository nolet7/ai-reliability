#!/usr/bin/env python3
"""
Phase 16 - Dynatrace Live Dashboard Import Automation

Purpose:
  Attempt to create a live Dynatrace dashboard automatically from the
  AS AI Reliability dashboard-as-code definition.

Why:
  Phase 14 generated the dashboard design as code.
  Phase 16 attempts actual live dashboard creation in Dynatrace.

Behavior:
  - Reads dynatrace/dashboards/as-ai-reliability-slo-command-center.json
  - Generates a Dynatrace-friendly dashboard payload
  - Probes available API endpoints
  - Attempts dashboard creation where supported
  - Captures exact API responses for evidence
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Tuple


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/dynatrace-live-dashboard-import"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "dynatrace-live-dashboard-import-summary.md"
JSON_REPORT = REPORT_ROOT / "dynatrace-live-dashboard-import-report.json"

DASHBOARD_SOURCE = Path(
    os.getenv(
        "DASHBOARD_SOURCE",
        "dynatrace/dashboards/as-ai-reliability-slo-command-center.json",
    )
)

RAW_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


DYNATRACE_ENV_URL = env("DYNATRACE_ENV_URL").rstrip("/")
DYNATRACE_API_TOKEN = env("DYNATRACE_API_TOKEN")

APP_NAME = env("APP_NAME", "as-ai-quality-service")
ENVIRONMENT = env("ENVIRONMENT", "poc")
ENABLE_CREATE = env("DYNATRACE_DASHBOARD_ENABLE_CREATE", "true").lower() in {"true", "1", "yes"}


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=False), encoding="utf-8")


def dt_request(method: str, path: str, payload: Dict[str, Any] | None = None) -> Tuple[int, Any]:
    if not DYNATRACE_ENV_URL or not DYNATRACE_API_TOKEN:
        return 0, "DYNATRACE_ENV_URL or DYNATRACE_API_TOKEN missing"

    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url=f"{DYNATRACE_ENV_URL}{path}",
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


def load_dashboard_source() -> Dict[str, Any]:
    if not DASHBOARD_SOURCE.exists():
        raise FileNotFoundError(f"Dashboard source not found: {DASHBOARD_SOURCE}")

    return json.loads(DASHBOARD_SOURCE.read_text(encoding="utf-8"))


def convert_to_classic_dashboard_payload(source: Dict[str, Any]) -> Dict[str, Any]:
    """
    Creates a conservative classic-dashboard-style payload.

    Some Dynatrace tenants may not accept this exact payload depending on
    dashboard generation/version. The API response will tell us whether this
    tenant supports this endpoint and token scope.
    """

    tiles = []
    x = 0
    y = 0

    for idx, tile in enumerate(source.get("tiles", [])):
        metric = tile.get("metric", "")
        title = tile.get("title", f"Tile {idx + 1}")

        tile_type = "DATA_EXPLORER"

        tiles.append(
            {
                "name": title,
                "tileType": tile_type,
                "configured": True,
                "bounds": {
                    "top": y,
                    "left": x,
                    "width": 456,
                    "height": 304,
                },
                "tileFilter": {},
                "queries": [
                    {
                        "id": f"query-{idx + 1}",
                        "metricSelector": metric,
                    }
                ],
                "visualConfig": {
                    "type": "SINGLE_VALUE" if tile.get("type") == "single_value" else "GRAPH_CHART",
                    "global": {},
                    "rules": [],
                    "axes": {},
                    "heatmapSettings": {},
                    "thresholds": [],
                },
            }
        )

        x += 456
        if x >= 1368:
            x = 0
            y += 304

    return {
        "dashboardMetadata": {
            "name": source.get("name", "AS AI Reliability SLO Command Center"),
            "shared": False,
            "owner": "GitHub Actions",
            "tags": ["as-ai-reliability", ENVIRONMENT, APP_NAME],
            "preset": False,
        },
        "tiles": tiles,
    }


def main() -> int:
    started = now_utc()
    source = load_dashboard_source()

    classic_payload = convert_to_classic_dashboard_payload(source)
    write_json(RAW_DIR / "classic_dashboard_payload.json", classic_payload)

    api_results: Dict[str, Any] = {}

    probes = {
        "classic_dashboards_list": ("GET", "/api/config/v1/dashboards"),
        "settings_schemas": ("GET", "/api/v2/settings/schemas"),
    }

    for name, (method, path) in probes.items():
        status, body = dt_request(method, path)
        api_results[name] = {
            "http_status": status,
            "response": body,
        }
        write_json(RAW_DIR / f"{name}.json", api_results[name])

    create_status = 0
    create_body: Any = "Create disabled"

    if ENABLE_CREATE:
        create_status, create_body = dt_request(
            "POST",
            "/api/config/v1/dashboards",
            classic_payload,
        )

    api_results["classic_dashboard_create"] = {
        "http_status": create_status,
        "response": create_body,
    }
    write_json(RAW_DIR / "classic_dashboard_create_response.json", api_results["classic_dashboard_create"])

    created = 200 <= int(create_status or 0) < 300

    report = {
        "phase": "Phase 16 - Dynatrace Live Dashboard Import Automation",
        "started_utc": started,
        "app": APP_NAME,
        "environment": ENVIRONMENT,
        "dashboard_source": str(DASHBOARD_SOURCE),
        "enable_create": ENABLE_CREATE,
        "created": created,
        "create_http_status": create_status,
        "api_results": api_results,
    }
    write_json(JSON_REPORT, report)

    lines = [
        "# Dynatrace Live Dashboard Import Automation Summary",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| App | {APP_NAME} |",
        f"| Environment | {ENVIRONMENT} |",
        f"| Dashboard Source | `{DASHBOARD_SOURCE}` |",
        f"| Create Enabled | {ENABLE_CREATE} |",
        f"| Dashboard Created | {created} |",
        f"| Create HTTP Status | {create_status} |",
        "",
        "## API Results",
        "",
        "| API Step | HTTP Status | Meaning |",
        "|---|---:|---|",
    ]

    for name, result in api_results.items():
        status = int(result.get("http_status") or 0)
        if 200 <= status < 300:
            meaning = "Success"
        elif status == 401:
            meaning = "Unauthorized token"
        elif status == 403:
            meaning = "Token lacks dashboard/config write permission"
        elif status == 404:
            meaning = "Endpoint unavailable in this Dynatrace tenant/API generation"
        else:
            meaning = "Review raw response"
        lines.append(f"| {name} | {status} | {meaning} |")

    lines.extend(
        [
            "",
            "## Evidence Files",
            "",
            "- `dynatrace-live-dashboard-import-summary.md`",
            "- `dynatrace-live-dashboard-import-report.json`",
            "- `raw/classic_dashboard_payload.json`",
            "- `raw/classic_dashboard_create_response.json`",
            "- `raw/classic_dashboards_list.json`",
            "- `raw/settings_schemas.json`",
        ]
    )

    SUMMARY_MD.write_text("\n".join(lines), encoding="utf-8")

    print(f"Dynatrace dashboard created: {created}")
    print(f"Create HTTP status: {create_status}")
    print(f"Summary: {SUMMARY_MD}")

    return 0 if created else 1


if __name__ == "__main__":
    raise SystemExit(main())
