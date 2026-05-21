#!/usr/bin/env bash

# scripts/atlas.sh
#
# Purpose:
# Runs Atlas CLI using the official Atlas Docker image.
#
# This version is Git Bash safe on Windows.
#
# Why this fix exists:
# Git Bash can incorrectly convert Linux container paths such as /workspace
# into Windows paths like C:/Program Files/Git/workspace.
#
# MSYS_NO_PATHCONV=1 prevents Git Bash from rewriting container paths.
# HOST_WORKDIR uses a Windows-formatted path for the Docker volume mount.

set -euo pipefail

if command -v cygpath >/dev/null 2>&1; then
  HOST_WORKDIR="$(cygpath -w "$(pwd)")"
else
  HOST_WORKDIR="$(pwd)"
fi

MSYS_NO_PATHCONV=1 docker run --rm \
  --network as-poc-net \
  -v "${HOST_WORKDIR}:/workspace" \
  -w /workspace \
  arigaio/atlas:latest "$@"
