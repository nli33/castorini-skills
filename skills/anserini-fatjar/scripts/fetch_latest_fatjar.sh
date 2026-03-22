#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${ANSERINI_MAVEN_BASE_URL:-https://repo1.maven.org/maven2/io/anserini/anserini}"
METADATA_URL="${BASE_URL%/}/maven-metadata.xml"
VERSION="${1:-${ANSERINI_VERSION:-}}"

if [[ -z "${VERSION}" ]]; then
  METADATA="$(wget -qO- "${METADATA_URL}")"
  VERSION="$(printf '%s' "${METADATA}" | tr -d '\n' | sed -n 's:.*<release>\([^<]*\)</release>.*:\1:p')"
  if [[ -z "${VERSION}" ]]; then
    VERSION="$(printf '%s' "${METADATA}" | tr -d '\n' | sed -n 's:.*<latest>\([^<]*\)</latest>.*:\1:p')"
  fi
fi

if [[ -z "${VERSION}" ]]; then
  echo "Failed to resolve the latest Anserini version from ${METADATA_URL}" >&2
  exit 1
fi

JAR_NAME="anserini-${VERSION}-fatjar.jar"
JAR_URL="${BASE_URL%/}/${VERSION}/${JAR_NAME}"

echo "Resolved Anserini version: ${VERSION}"
echo "Downloading ${JAR_URL}"
wget "${JAR_URL}"
echo "Downloaded ${JAR_NAME}"
