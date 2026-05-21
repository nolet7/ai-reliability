# app/main.py
#
# Purpose:
# This FastAPI service represents the POC AI reliability service.
# It exposes health checks, model visibility, prediction audit evidence,
# and incident simulation endpoints for Dynatrace, ServiceNow, Atlas, and CI/CD release gates.
#
# Service name:
# as-ai-quality-service
#
# Main SRE reliability endpoints:
# - /health/live
# - /health/ready
# - /health/model
# - /version
# - /predict
# - /simulate-latency
# - /simulate-error

import json
import os
import random
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider


# ------------------------------------------------------------
# Application metadata
# ------------------------------------------------------------
# These values can later be injected using Kubernetes ConfigMap,
# environment variables, Helm values, or CI/CD deployment variables.

SERVICE_NAME = os.getenv("SERVICE_NAME", "as-ai-quality-service")
ENVIRONMENT = os.getenv("ENVIRONMENT", "poc")
OWNER = os.getenv("OWNER", "sre-platform-team")

MODEL_NAME = os.getenv("MODEL_NAME", "as-quality-classifier")
MODEL_VERSION = os.getenv("MODEL_VERSION", "v1.0.3")

# ARTIFACT_LOADED represents whether the model artifact was loaded successfully.
# In the POC, this is controlled by an environment variable.
# Later, this can be changed to check a real model file or object storage artifact.
ARTIFACT_LOADED = os.getenv("ARTIFACT_LOADED", "true").lower() == "true"

# AUDIT_REQUIRED controls whether prediction requests must be written to audit.
AUDIT_REQUIRED = os.getenv("AUDIT_REQUIRED", "true").lower() == "true"

# This local file stores prediction audit records during the POC.
# Later, this can move to PostgreSQL.
AUDIT_LOG_PATH = Path(os.getenv("AUDIT_LOG_PATH", "local/generated/audit/prediction_audit.jsonl"))

# DB_CHECK_ENABLED is false for Phase 2.
# In Phase 4, we will turn this into a real PostgreSQL readiness check.
DB_CHECK_ENABLED = os.getenv("DB_CHECK_ENABLED", "false").lower() == "true"

# OpenTelemetry basic tracing toggle.
# For now, this enables local instrumentation only.
# Dynatrace export will be added later.
OTEL_ENABLED = os.getenv("OTEL_ENABLED", "true").lower() == "true"
OTEL_EXPORTER_OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "").strip()


# ------------------------------------------------------------
# FastAPI application setup
# ------------------------------------------------------------

app = FastAPI(
    title="AS AI Quality Service",
    description="POC AI reliability service with health checks, model visibility, prediction audit, and incident simulation.",
    version="1.0.0",
)


# ------------------------------------------------------------
# OpenTelemetry basic setup
# ------------------------------------------------------------

def configure_opentelemetry() -> None:
    # Enables OpenTelemetry tracing for FastAPI.
    #
    # In this step, traces are created inside the application process.
    # We are not exporting to Dynatrace yet.
    #
    # Later, we will add OTLP export to Dynatrace or an OpenTelemetry Collector.

    if not OTEL_ENABLED:
        return

    resource = Resource.create(
        {
            "service.name": SERVICE_NAME,
            "service.namespace": "as-ai-reliability",
            "deployment.environment": ENVIRONMENT,
            "service.version": MODEL_VERSION,
            "model.name": MODEL_NAME,
            "model.version": MODEL_VERSION,
            "team.owner": OWNER,
        }
    )

    provider = TracerProvider(resource=resource)
    trace.set_tracer_provider(provider)

    # If OTEL_EXPORTER_OTLP_ENDPOINT is configured, export traces using OTLP HTTP.
    # The OTLPSpanExporter reads standard OTEL environment variables such as:
    # - OTEL_EXPORTER_OTLP_ENDPOINT
    # - OTEL_EXPORTER_OTLP_HEADERS
    # - OTEL_EXPORTER_OTLP_PROTOCOL
    #
    # For Dynatrace, the endpoint should be:
    # https://YOUR_ENVIRONMENT.live.dynatrace.com/api/v2/otlp
    if OTEL_EXPORTER_OTLP_ENDPOINT:
        exporter = OTLPSpanExporter()
        provider.add_span_processor(BatchSpanProcessor(exporter))

    FastAPIInstrumentor.instrument_app(app)


configure_opentelemetry()

tracer = trace.get_tracer(__name__)


# ------------------------------------------------------------
# Request and response models
# ------------------------------------------------------------

class PredictionRequest(BaseModel):
    # asset_id represents the asset or equipment being evaluated.
    asset_id: str = Field(..., example="asset-1001")

    # site_id represents the facility, plant, or location.
    site_id: str = Field(..., example="site-as-poc-001")

    # sensor_score is a simplified numeric signal used for the POC prediction.
    sensor_score: float = Field(..., ge=0, le=100, example=87.5)

    # audit_required allows the caller to explicitly request audit behavior.
    audit_required: bool = Field(default=True, example=True)


class PredictionResponse(BaseModel):
    request_id: str
    trace_id: str
    service_name: str
    environment: str
    model_name: str
    model_version: str
    artifact_loaded: bool
    prediction_status: str
    quality_risk: str
    confidence: float
    audit_required: bool
    audit_logged: bool
    timestamp_utc: str


# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

def utc_now() -> str:
    # Returns an ISO-8601 UTC timestamp for logs and audit records.
    return datetime.now(timezone.utc).isoformat()


def generate_trace_id(x_trace_id: Optional[str]) -> str:
    # If the caller sends a trace ID header, use it.
    # Otherwise, generate a UUID-based trace ID for local POC correlation.
    if x_trace_id:
        return x_trace_id
    return uuid.uuid4().hex


def ensure_audit_directory() -> None:
    # Creates the local audit directory if it does not already exist.
    AUDIT_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)


def write_audit_record(record: dict) -> bool:
    # Writes one JSON audit record per line.
    # This is intentionally simple for the POC.
    # In Phase 4, PostgreSQL will become the durable audit store.
    try:
        ensure_audit_directory()
        with AUDIT_LOG_PATH.open("a", encoding="utf-8") as file:
            file.write(json.dumps(record) + "\n")
        return True
    except Exception:
        return False


def calculate_quality_risk(sensor_score: float) -> tuple[str, float]:
    # Simple deterministic POC scoring logic.
    # Higher sensor_score means lower quality risk.
    if sensor_score >= 85:
        return "low", round(random.uniform(0.91, 0.98), 2)
    if sensor_score >= 60:
        return "medium", round(random.uniform(0.72, 0.88), 2)
    return "high", round(random.uniform(0.61, 0.79), 2)


def database_ready() -> bool:
    # Placeholder for database readiness.
    # During Phase 2, this returns true unless DB_CHECK_ENABLED is set.
    # During Phase 4, this will be replaced with a real PostgreSQL check.
    if not DB_CHECK_ENABLED:
        return True

    # This intentionally returns false until PostgreSQL is implemented.
    return False


# ------------------------------------------------------------
# Root endpoint
# ------------------------------------------------------------

@app.get("/")
def root():
    # Simple landing endpoint to identify the service.
    return {
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "message": "AS AI Reliability Incident Automation POC service is running",
        "available_endpoints": [
            "/health/live",
            "/health/ready",
            "/health/model",
            "/version",
            "/predict",
            "/simulate-latency",
            "/simulate-error",
        ],
    }


# ------------------------------------------------------------
# Health check endpoints
# ------------------------------------------------------------

@app.get("/health/live")
def health_live():
    # Liveness check:
    # Used by Kubernetes to confirm the process is alive.
    # This should stay lightweight and should not depend on external services.
    return {
        "status": "live",
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "timestamp_utc": utc_now(),
    }


@app.get("/health/ready")
def health_ready():
    # Readiness check:
    # Used by Kubernetes to decide whether traffic should be sent to the pod.
    # This checks model status and database readiness placeholder.
    model_ready = ARTIFACT_LOADED
    db_ready = database_ready()

    ready = model_ready and db_ready

    if not ready:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "service_name": SERVICE_NAME,
                "environment": ENVIRONMENT,
                "model_ready": model_ready,
                "database_ready": db_ready,
                "timestamp_utc": utc_now(),
            },
        )

    return {
        "status": "ready",
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "model_ready": model_ready,
        "database_ready": db_ready,
        "timestamp_utc": utc_now(),
    }


@app.get("/health/model")
def health_model():
    # Model health check:
    # Confirms the model artifact is loaded and exposes model metadata.
    status = "model_ready" if ARTIFACT_LOADED else "model_not_loaded"

    if not ARTIFACT_LOADED:
        raise HTTPException(
            status_code=503,
            detail={
                "status": status,
                "service_name": SERVICE_NAME,
                "model_name": MODEL_NAME,
                "model_version": MODEL_VERSION,
                "artifact_loaded": ARTIFACT_LOADED,
                "environment": ENVIRONMENT,
                "timestamp_utc": utc_now(),
            },
        )

    return {
        "status": status,
        "service_name": SERVICE_NAME,
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "artifact_loaded": ARTIFACT_LOADED,
        "environment": ENVIRONMENT,
        "owner": OWNER,
        "timestamp_utc": utc_now(),
    }


@app.get("/version")
def version():
    # Version endpoint:
    # Used by SREs, CI/CD gates, Dynatrace tagging, and incident evidence capture.
    return {
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "owner": OWNER,
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "artifact_loaded": ARTIFACT_LOADED,
        "audit_required_default": AUDIT_REQUIRED,
        "timestamp_utc": utc_now(),
    }


# ------------------------------------------------------------
# Prediction endpoint
# ------------------------------------------------------------

@app.post("/predict", response_model=PredictionResponse)
def predict(payload: PredictionRequest, x_trace_id: Optional[str] = Header(default=None)):
    # Prediction endpoint:
    # Simulates an AI quality prediction request.
    # It generates request_id, trace_id, model metadata, and audit evidence.
    #
    # OpenTelemetry:
    # The active request span is enriched with AS-specific attributes.
    # These attributes later help Dynatrace and ServiceNow correlate prediction behavior
    # with model version, audit status, request ID, and trace ID.

    current_span = trace.get_current_span()
    current_span.set_attribute("as.service_name", SERVICE_NAME)
    current_span.set_attribute("as.environment", ENVIRONMENT)
    current_span.set_attribute("as.model_name", MODEL_NAME)
    current_span.set_attribute("as.model_version", MODEL_VERSION)
    current_span.set_attribute("as.artifact_loaded", ARTIFACT_LOADED)
    current_span.set_attribute("as.audit_required_input", payload.audit_required)
    current_span.set_attribute("as.asset_id", payload.asset_id)
    current_span.set_attribute("as.site_id", payload.site_id)
    current_span.set_attribute("as.sensor_score", payload.sensor_score)

    if not ARTIFACT_LOADED:
        raise HTTPException(
            status_code=503,
            detail={
                "error": "model_artifact_not_loaded",
                "service_name": SERVICE_NAME,
                "model_name": MODEL_NAME,
                "model_version": MODEL_VERSION,
                "artifact_loaded": ARTIFACT_LOADED,
                "timestamp_utc": utc_now(),
            },
        )

    request_id = f"req-{uuid.uuid4().hex[:12]}"
    trace_id = generate_trace_id(x_trace_id)

    current_span.set_attribute("as.request_id", request_id)
    current_span.set_attribute("as.trace_id", trace_id)

    quality_risk, confidence = calculate_quality_risk(payload.sensor_score)

    audit_required = AUDIT_REQUIRED or payload.audit_required

    response = {
        "request_id": request_id,
        "trace_id": trace_id,
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "artifact_loaded": ARTIFACT_LOADED,
        "prediction_status": "success",
        "quality_risk": quality_risk,
        "confidence": confidence,
        "audit_required": audit_required,
        "audit_logged": False,
        "timestamp_utc": utc_now(),
    }

    audit_record = {
        **response,
        "asset_id": payload.asset_id,
        "site_id": payload.site_id,
        "sensor_score": payload.sensor_score,
        "owner": OWNER,
    }

    if audit_required:
        # Store the final audit status in the audit record itself.
        # This makes the API response and local audit file consistent.
        audit_record["audit_logged"] = True
        response["audit_logged"] = write_audit_record(audit_record)

    current_span.set_attribute("as.audit_required", response["audit_required"])
    current_span.set_attribute("as.audit_logged", response["audit_logged"])
    current_span.set_attribute("as.prediction_status", response["prediction_status"])
    current_span.set_attribute("as.quality_risk", response["quality_risk"])
    current_span.set_attribute("as.confidence", response["confidence"])

    return response


# ------------------------------------------------------------
# Incident simulation endpoints
# ------------------------------------------------------------

@app.get("/simulate-latency")
def simulate_latency(seconds: float = 2.0):
    # Simulates slow application behavior.
    # Dynatrace should detect this if enough traffic is generated.
    # CI/CD can also use this endpoint to test rollback behavior.
    if seconds < 0:
        seconds = 0
    if seconds > 10:
        seconds = 10

    time.sleep(seconds)

    return {
        "status": "latency_simulated",
        "service_name": SERVICE_NAME,
        "environment": ENVIRONMENT,
        "delay_seconds": seconds,
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "timestamp_utc": utc_now(),
    }


@app.get("/simulate-error")
def simulate_error():
    # Simulates a controlled 500 error.
    # This is used to test Dynatrace problem detection and ServiceNow incident routing.
    raise HTTPException(
        status_code=500,
        detail={
            "error": "simulated_application_error",
            "service_name": SERVICE_NAME,
            "environment": ENVIRONMENT,
            "model_name": MODEL_NAME,
            "model_version": MODEL_VERSION,
            "timestamp_utc": utc_now(),
        },
    )
