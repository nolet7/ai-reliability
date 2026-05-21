#!/usr/bin/env python3
"""
Phase 6 - ServiceNow Incident-on-Failure Automation

Purpose:
  Create or update a ServiceNow incident when a GitHub Actions release gate fails.

Enterprise value:
  This connects release automation, runtime validation, observability validation,
  and ITSM incident management. It prevents silent release failures and gives SRE,
  platform, support, and change-management teams an auditable operational record.

Duplicate detection:
  Uses ServiceNow incident correlation_id so repeated failures from the same
  app/environment/workflow update the same active incident instead of creating noise.
"""

import base64
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


REPORT_ROOT = Path(os.getenv("REPORT_ROOT", "reports/servicenow-incident"))
RAW_DIR = REPORT_ROOT / "raw"
SUMMARY_MD = REPORT_ROOT / "servicenow-incident-summary.md"
JSON_REPORT = REPORT_ROOT / "servicenow-incident-report.json"

RAW_DIR.mkdir(parents=True, exist_ok=True)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def optional_servicenow_ref(name: str) -> str:
    """
    GitHub Actions variables cannot be empty.
    Use SKIP, NONE, NULL, N/A, or __NONE__ when you do not want to send
    an optional ServiceNow reference field like business_service or cmdb_ci.
    """
    value = env(name)
    if value.upper() in {"SKIP", "NONE", "NULL", "N/A", "__NONE__"}:
        return ""
    return value


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class ServiceNowClient:
    def __init__(self, instance_url: str, username: str, password: str) -> None:
        self.instance_url = instance_url.rstrip("/")
        self.username = username
        self.password = password

    def _headers(self) -> Dict[str, str]:
        token = base64.b64encode(
            f"{self.username}:{self.password}".encode("utf-8")
        ).decode("utf-8")

        return {
            "Authorization": f"Basic {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def request(
        self,
        method: str,
        path: str,
        payload: Optional[Dict[str, Any]] = None,
    ) -> Tuple[int, Dict[str, Any]]:
        url = f"{self.instance_url}{path}"
        body = None

        if payload is not None:
            body = json.dumps(payload).encode("utf-8")

        request = urllib.request.Request(
            url=url,
            data=body,
            headers=self._headers(),
            method=method,
        )

        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                status_code = response.getcode()
                response_body = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            status_code = exc.code
            response_body = exc.read().decode("utf-8", errors="replace")
        except Exception as exc:
            return 0, {"error": str(exc)}

        try:
            parsed = json.loads(response_body) if response_body else {}
        except Exception:
            parsed = {"raw": response_body}

        return status_code, parsed

    def find_active_incident_by_correlation_id(
        self,
        correlation_id: str,
    ) -> Tuple[int, Dict[str, Any]]:
        query = f"active=true^correlation_id={correlation_id}"
        encoded_query = urllib.parse.quote(query, safe="")
        fields = "sys_id,number,state,short_description,correlation_id,opened_at,sys_updated_on"

        path = (
            "/api/now/table/incident"
            f"?sysparm_query={encoded_query}"
            f"&sysparm_fields={fields}"
            "&sysparm_limit=1"
        )

        return self.request("GET", path)

    def create_incident(self, payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        return self.request("POST", "/api/now/table/incident", payload)

    def update_incident(
        self,
        sys_id: str,
        payload: Dict[str, Any],
    ) -> Tuple[int, Dict[str, Any]]:
        return self.request("PATCH", f"/api/now/table/incident/{sys_id}", payload)


def build_context() -> Dict[str, str]:
    github_server_url = env("GITHUB_SERVER_URL", "https://github.com")
    github_repository = env("GITHUB_REPOSITORY", "nolet7/ai-reliability")
    github_run_id = env("GITHUB_RUN_ID")
    github_run_number = env("GITHUB_RUN_NUMBER")
    github_sha = env("GITHUB_SHA")
    github_ref_name = env("GITHUB_REF_NAME", env("GITHUB_REF"))

    workflow_name = env(
        "FAILED_WORKFLOW_NAME",
        env("GITHUB_WORKFLOW", "unknown-workflow"),
    )
    workflow_conclusion = env("FAILED_WORKFLOW_CONCLUSION", "failure")
    workflow_run_url = env("FAILED_WORKFLOW_RUN_URL")

    current_run_url = (
        f"{github_server_url}/{github_repository}/actions/runs/{github_run_id}"
        if github_run_id
        else ""
    )

    if not workflow_run_url:
        workflow_run_url = current_run_url

    app_name = env("APP_NAME", "as-ai-quality-service")
    namespace = env("NAMESPACE", "ai-reliability-poc")
    environment = env("ENVIRONMENT", "poc")
    expected_model_version = env("EXPECTED_MODEL_VERSION", "v1.0.3")

    severity = env("SERVICENOW_SEVERITY", "2")
    impact = env("SERVICENOW_IMPACT", "2")
    urgency = env("SERVICENOW_URGENCY", "2")

    correlation_id = env(
        "SERVICENOW_CORRELATION_ID",
        f"as-ai-reliability:{environment}:{app_name}:{workflow_name}:release-gate-failure",
    )

    return {
        "github_server_url": github_server_url,
        "github_repository": github_repository,
        "github_run_id": github_run_id,
        "github_run_number": github_run_number,
        "github_sha": github_sha,
        "github_ref_name": github_ref_name,
        "current_run_url": current_run_url,
        "workflow_name": workflow_name,
        "workflow_conclusion": workflow_conclusion,
        "workflow_run_url": workflow_run_url,
        "app_name": app_name,
        "namespace": namespace,
        "environment": environment,
        "expected_model_version": expected_model_version,
        "severity": severity,
        "impact": impact,
        "urgency": urgency,
        "correlation_id": correlation_id,
    }


def build_description(context: Dict[str, str]) -> str:
    return f"""
Automated ServiceNow incident created by AS AI Reliability POC release automation.

Failure Summary:
- Application: {context["app_name"]}
- Environment: {context["environment"]}
- Kubernetes Namespace: {context["namespace"]}
- Failed Workflow: {context["workflow_name"]}
- Workflow Conclusion: {context["workflow_conclusion"]}
- Expected Model Version: {context["expected_model_version"]}
- GitHub Repository: {context["github_repository"]}
- Branch/Ref: {context["github_ref_name"]}
- Commit SHA: {context["github_sha"]}
- GitHub Run Number: {context["github_run_number"]}
- Failed Workflow URL: {context["workflow_run_url"]}
- Incident Automation Run URL: {context["current_run_url"]}
- Correlation ID: {context["correlation_id"]}

Operational Impact:
A release validation, runtime validation, observability validation, or canary validation gate failed.
The AI reliability service should not be promoted until SRE/platform review is complete.

Recommended Triage:
1. Review the failed GitHub Actions workflow logs.
2. Download the workflow evidence artifact.
3. Validate Kubernetes rollout, pod readiness, service routing, and Istio routing.
4. Validate /health, /model, and /predict endpoint results.
5. Validate Dynatrace service visibility, metrics, traces, and open problems.
6. If runtime behavior is unhealthy, execute rollback workflow and attach rollback evidence.
7. Document RCA and decide whether this becomes a problem-management item.
""".strip()


def build_work_notes(context: Dict[str, str], mode: str) -> str:
    return f"""
[{now_utc()}] Automated incident {mode} by AS AI Reliability POC.

Evidence:
- Failed workflow: {context["workflow_name"]}
- Conclusion: {context["workflow_conclusion"]}
- GitHub evidence URL: {context["workflow_run_url"]}
- Current automation run: {context["current_run_url"]}
- Repository: {context["github_repository"]}
- Commit: {context["github_sha"]}
- Branch/ref: {context["github_ref_name"]}
- App: {context["app_name"]}
- Namespace: {context["namespace"]}
- Environment: {context["environment"]}
- Expected model version: {context["expected_model_version"]}
- Correlation ID: {context["correlation_id"]}

Next action:
SRE should review the evidence artifact and decide whether to rollback, retry deployment,
adjust canary weights, or open a problem record.
""".strip()


def finish_report(
    result: Dict[str, Any],
    summary_lines: list,
    exit_code: int,
) -> int:
    result["finished_at_utc"] = now_utc()

    summary_lines.extend(
        [
            "",
            "## Incident Summary",
            "",
            "| Metric | Value |",
            "|---|---|",
            f"| Final Status | {result.get('status', 'unknown')} |",
            f"| Incident Action | {result.get('incident_action', 'none')} |",
            f"| Incident Number | {result.get('incident_number', '')} |",
            f"| Incident Sys ID | {result.get('incident_sys_id', '')} |",
            f"| ServiceNow HTTP Status | {result.get('servicenow_http_status', '')} |",
            f"| Finished UTC | {result['finished_at_utc']} |",
            "",
            "## Evidence Files",
            "",
            "- `servicenow-incident-summary.md`",
            "- `servicenow-incident-report.json`",
            "- `raw/incident_lookup_response.json`",
            "- `raw/incident_create_response.json` or `raw/incident_update_response.json`",
        ]
    )

    write_json(JSON_REPORT, result)
    SUMMARY_MD.write_text("\n".join(summary_lines), encoding="utf-8")

    print(f"ServiceNow automation status: {result.get('status', 'unknown')}")
    print(f"Incident action: {result.get('incident_action', 'none')}")
    print(f"Incident number: {result.get('incident_number', '')}")
    print(f"Summary report: {SUMMARY_MD}")
    print(f"JSON report: {JSON_REPORT}")

    return exit_code


def main() -> int:
    started_at = now_utc()
    context = build_context()

    enabled = env("SERVICENOW_ENABLE_INCIDENTS", "true").lower()
    instance_url = env("SERVICENOW_INSTANCE_URL")
    username = env("SERVICENOW_USERNAME")
    password = env("SERVICENOW_PASSWORD")

    summary_lines = [
        "# AS AI Reliability ServiceNow Incident Automation Report",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| Started UTC | {started_at} |",
        f"| Application | {context['app_name']} |",
        f"| Environment | {context['environment']} |",
        f"| Namespace | {context['namespace']} |",
        f"| Failed Workflow | {context['workflow_name']} |",
        f"| Workflow Conclusion | {context['workflow_conclusion']} |",
        f"| GitHub Run URL | {context['workflow_run_url']} |",
        f"| Correlation ID | {context['correlation_id']} |",
        "",
        "## Gate Results",
        "",
        "| Status | Gate | Evidence |",
        "|---|---|---|",
    ]

    result: Dict[str, Any] = {
        "phase": "Phase 6 - ServiceNow Incident-on-Failure Automation",
        "started_at_utc": started_at,
        "status": "unknown",
        "context": context,
        "incident_action": "none",
        "incident_number": "",
        "incident_sys_id": "",
        "servicenow_http_status": None,
    }

    if enabled not in {"true", "1", "yes"}:
        summary_lines.append(
            "| WARN | ServiceNow incident automation enabled | "
            "SERVICENOW_ENABLE_INCIDENTS is not true; no incident created |"
        )
        result["status"] = "skipped"
        result["reason"] = "SERVICENOW_ENABLE_INCIDENTS is not true"
        return finish_report(result, summary_lines, 0)

    missing = []

    if not instance_url:
        missing.append("SERVICENOW_INSTANCE_URL")

    if not username:
        missing.append("SERVICENOW_USERNAME")

    if not password:
        missing.append("SERVICENOW_PASSWORD")

    if missing:
        summary_lines.append(
            f"| FAIL | Required ServiceNow configuration | Missing: {', '.join(missing)} |"
        )
        result["status"] = "failed"
        result["reason"] = f"Missing required config: {', '.join(missing)}"
        return finish_report(result, summary_lines, 1)

    summary_lines.append(
        "| PASS | Required ServiceNow configuration | Instance URL and credentials are present |"
    )

    client = ServiceNowClient(instance_url, username, password)

    lookup_status, lookup_response = client.find_active_incident_by_correlation_id(
        context["correlation_id"]
    )
    write_json(RAW_DIR / "incident_lookup_response.json", lookup_response)

    if 200 <= lookup_status < 300:
        summary_lines.append(
            f"| PASS | Duplicate incident lookup | ServiceNow lookup returned HTTP {lookup_status} |"
        )
    else:
        summary_lines.append(
            f"| FAIL | Duplicate incident lookup | ServiceNow lookup returned HTTP {lookup_status} |"
        )
        result["status"] = "failed"
        result["servicenow_http_status"] = lookup_status
        result["lookup_response"] = lookup_response
        return finish_report(result, summary_lines, 1)

    existing = None
    records = lookup_response.get("result", [])

    if isinstance(records, list) and records:
        existing = records[0]

    short_description = (
        f"AS AI Reliability release gate failure - "
        f"{context['app_name']} - {context['environment']} - {context['workflow_name']}"
    )

    assignment_group = optional_servicenow_ref("SERVICENOW_ASSIGNMENT_GROUP")
    business_service = optional_servicenow_ref("SERVICENOW_BUSINESS_SERVICE")
    configuration_item = optional_servicenow_ref("SERVICENOW_CONFIGURATION_ITEM")

    base_payload: Dict[str, Any] = {
        "short_description": short_description,
        "description": build_description(context),
        "category": env("SERVICENOW_CATEGORY", "software"),
        "subcategory": env("SERVICENOW_SUBCATEGORY", "release"),
        "impact": context["impact"],
        "urgency": context["urgency"],
        "severity": context["severity"],
        "correlation_id": context["correlation_id"],
        "correlation_display": "GitHub Actions Release Gate",
        "work_notes": build_work_notes(context, "created"),
    }

    # Optional reference fields:
    # Only send these when you have a valid ServiceNow sys_id or accepted display value.
    if assignment_group:
        base_payload["assignment_group"] = assignment_group

    if business_service:
        base_payload["business_service"] = business_service

    if configuration_item:
        base_payload["cmdb_ci"] = configuration_item

    if existing:
        sys_id = existing.get("sys_id", "")

        update_payload = {
            "work_notes": build_work_notes(context, "updated"),
        }

        update_status, update_response = client.update_incident(sys_id, update_payload)
        write_json(RAW_DIR / "incident_update_response.json", update_response)

        if 200 <= update_status < 300:
            incident = update_response.get("result", {})
            result["status"] = "passed"
            result["incident_action"] = "updated"
            result["incident_number"] = incident.get("number", existing.get("number", ""))
            result["incident_sys_id"] = incident.get("sys_id", sys_id)
            result["servicenow_http_status"] = update_status

            summary_lines.append(
                "| PASS | Duplicate detection | Existing active incident found and updated |"
            )
            summary_lines.append(
                f"| PASS | Incident updated | "
                f"{result['incident_number']} / {result['incident_sys_id']} |"
            )

            return finish_report(result, summary_lines, 0)

        result["status"] = "failed"
        result["incident_action"] = "update_failed"
        result["servicenow_http_status"] = update_status
        result["update_response"] = update_response

        summary_lines.append(
            f"| FAIL | Incident update | ServiceNow returned HTTP {update_status} |"
        )

        return finish_report(result, summary_lines, 1)

    create_status, create_response = client.create_incident(base_payload)
    write_json(RAW_DIR / "incident_create_response.json", create_response)

    if 200 <= create_status < 300:
        incident = create_response.get("result", {})
        result["status"] = "passed"
        result["incident_action"] = "created"
        result["incident_number"] = incident.get("number", "")
        result["incident_sys_id"] = incident.get("sys_id", "")
        result["servicenow_http_status"] = create_status

        summary_lines.append(
            "| PASS | Duplicate detection | No active duplicate incident found |"
        )
        summary_lines.append(
            f"| PASS | Incident created | "
            f"{result['incident_number']} / {result['incident_sys_id']} |"
        )

        return finish_report(result, summary_lines, 0)

    result["status"] = "failed"
    result["incident_action"] = "create_failed"
    result["servicenow_http_status"] = create_status
    result["create_response"] = create_response

    summary_lines.append(
        f"| FAIL | Incident creation | ServiceNow returned HTTP {create_status} |"
    )

    return finish_report(result, summary_lines, 1)


if __name__ == "__main__":
    sys.exit(main())
