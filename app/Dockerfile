# app/Dockerfile
#
# Purpose:
# Container image for the ASR AI Quality Service.
#
# This Dockerfile supports the ASR AI Reliability Incident Automation POC by:
# - Packaging the FastAPI application
# - Running the service on port 8000
# - Supporting Kubernetes health probes
# - Supporting Dynatrace/OpenTelemetry instrumentation later
# - Running as a non-root user for better runtime security

# Use a small official Python image.
FROM python:3.11-slim

# Set Python runtime options.
# PYTHONDONTWRITEBYTECODE prevents Python from writing .pyc files.
# PYTHONUNBUFFERED ensures logs are printed immediately.
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Define application metadata defaults.
# These can be overridden later by Docker, Kubernetes ConfigMap, Helm, or CI/CD.
ENV SERVICE_NAME=asr-ai-quality-service
ENV ENVIRONMENT=poc
ENV OWNER=sre-platform-team
ENV MODEL_NAME=asr-quality-classifier
ENV MODEL_VERSION=v1.0.3
ENV ARTIFACT_LOADED=true
ENV AUDIT_REQUIRED=true
ENV AUDIT_LOG_PATH=local/generated/audit/prediction_audit.jsonl
ENV DB_CHECK_ENABLED=false
ENV OTEL_ENABLED=true

# Set the working directory inside the container.
WORKDIR /app

# Install operating system packages needed for health checks and runtime operations.
# curl is useful for container-level diagnostics.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency file first to improve Docker layer caching.
COPY app/requirements.txt /app/requirements.txt

# Install Python dependencies.
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /app/requirements.txt

# Copy application code into the image.
COPY app /app/app

# Create local audit directory used by the POC.
RUN mkdir -p /app/local/generated/audit

# Create a non-root user for safer container runtime.
RUN useradd --create-home --shell /bin/bash appuser \
    && chown -R appuser:appuser /app

# Switch to non-root user.
USER appuser

# Expose FastAPI port.
EXPOSE 8000

# Container health check.
# Docker will call /health/live to confirm the app process is healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1:8000/health/live || exit 1

# Start the FastAPI service.
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
