#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORT="${ANSERINI_REST_PORT:-8080}"
HOST="${ANSERINI_REST_HOST:-127.0.0.1}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -f "${SERVER_LOG:-}"
}

trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

check_jdk_21() {
  local version_output
  version_output="$("$1" -version 2>&1 | head -n 1)"
  if [[ "${version_output}" != *"21."* && "${version_output}" != *" 21"* ]]; then
    echo "$1 is not JDK 21: ${version_output}" >&2
    exit 1
  fi
}

require_cmd java
require_cmd javac
require_cmd wget
require_cmd curl

check_jdk_21 java
check_jdk_21 javac

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found; continuing without jq-based JSON assertions" >&2
  HAVE_JQ=0
else
  HAVE_JQ=1
fi

if ! ls -1 anserini-*-fatjar.jar >/dev/null 2>&1; then
  bash "${SKILL_DIR}/scripts/fetch_latest_fatjar.sh"
fi

ANSERINI_JAR="$(ls -1 anserini-*-fatjar.jar | sort -V | tail -n 1)"
echo "Using ${ANSERINI_JAR}"

java -cp "${ANSERINI_JAR}" io.anserini.cli.Search --help >/dev/null

SMOKE_LOG="$(mktemp)"
java -cp "${ANSERINI_JAR}" \
  io.anserini.reproduce.ReproduceFromDocumentCollection \
  --download --index --verify --search --config cacm-download \
  2>&1 | tee "${SMOKE_LOG}" >/dev/null

grep -F "expected: 0.3123 actual: 0.3123" "${SMOKE_LOG}" >/dev/null
grep -F "expected: 0.1942 actual: 0.1942" "${SMOKE_LOG}" >/dev/null
rm -f "${SMOKE_LOG}"

PREBUILT_JSON="$(java -cp "${ANSERINI_JAR}" io.anserini.cli.PrebuiltIndexCatalog --list --filter '^msmarco-v1-passage$')"
TOPICS_JSON="$(java -cp "${ANSERINI_JAR}" io.anserini.cli.TopicsCatalog --list --filter '^msmarco-v1-passage-dev$')"

if [[ "${HAVE_JQ}" -eq 1 ]]; then
  printf '%s\n' "${PREBUILT_JSON}" | jq -e '.[0].name == "msmarco-v1-passage"' >/dev/null
  printf '%s\n' "${TOPICS_JSON}" | jq -e '.[0] == "msmarco-v1-passage-dev"' >/dev/null
else
  grep -F 'msmarco-v1-passage' <<<"${PREBUILT_JSON}" >/dev/null
  grep -F 'msmarco-v1-passage-dev' <<<"${TOPICS_JSON}" >/dev/null
fi

java -cp "${ANSERINI_JAR}" io.anserini.cli.TopicsCatalog --get msmarco-v1-passage-dev >/dev/null

SEARCH_JSON="$(java -cp "${ANSERINI_JAR}" \
  io.anserini.cli.Search \
  --index indexes/lucene-inverted.cacm.download \
  --query "computer programming" \
  --json --hits 2 2>/dev/null)"
SEARCH_TREC="$(java -cp "${ANSERINI_JAR}" \
  io.anserini.cli.Search \
  --index indexes/lucene-inverted.cacm.download \
  --query "computer programming" \
  --trec --hits 2 2>/dev/null)"
INTERACTIVE_JSON="$(printf 'computer programming\n' | java -cp "${ANSERINI_JAR}" \
  io.anserini.cli.Search \
  --index indexes/lucene-inverted.cacm.download \
  --interactive --json 2>/dev/null)"

if [[ "${HAVE_JQ}" -eq 1 ]]; then
  printf '%s\n' "${SEARCH_JSON}" | jq -e '.candidates[0].docid == "CACM-1771"' >/dev/null
  printf '%s\n' "${INTERACTIVE_JSON}" | jq -e '.candidates[0].docid == "CACM-1771"' >/dev/null
else
  grep -F '"docid":"CACM-1771"' <<<"${SEARCH_JSON}" >/dev/null
  grep -F '"docid":"CACM-1771"' <<<"${INTERACTIVE_JSON}" >/dev/null
fi
grep -F '1 Q0 CACM-1771 1 2.301000 anserini' <<<"${SEARCH_TREC}" >/dev/null

SERVER_LOG="$(mktemp)"
java -cp "${ANSERINI_JAR}" io.anserini.api.RestServer --host "${HOST}" --port "${PORT}" \
  >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 40); do
  if grep -F "Anserini REST server listening on ${HOST}:${PORT}" "${SERVER_LOG}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

grep -F "Anserini REST server listening on ${HOST}:${PORT}" "${SERVER_LOG}" >/dev/null

ROOT_RESPONSE="$(curl -sS -i "http://${HOST}:${PORT}/")"
SEARCH_RESPONSE="$(curl -sS "http://${HOST}:${PORT}/v1/indexes%2Flucene-inverted.cacm.download/search?query=computer%20programming&hits=2")"
DOC_RESPONSE="$(curl -sS "http://${HOST}:${PORT}/v1/indexes%2Flucene-inverted.cacm.download/doc/CACM-1771")"

grep -F 'Expected route /v1/{index}/search or /v1/{index}/doc/{docid}' <<<"${ROOT_RESPONSE}" >/dev/null
if [[ "${HAVE_JQ}" -eq 1 ]]; then
  printf '%s\n' "${SEARCH_RESPONSE}" | jq -e '.index == "indexes/lucene-inverted.cacm.download" and .candidates[0].docid == "CACM-1771"' >/dev/null
  printf '%s\n' "${DOC_RESPONSE}" | jq -e '.docid == "CACM-1771"' >/dev/null
else
  grep -F '"index":"indexes/lucene-inverted.cacm.download"' <<<"${SEARCH_RESPONSE}" >/dev/null
  grep -F '"docid":"CACM-1771"' <<<"${DOC_RESPONSE}" >/dev/null
fi

echo "Verified Anserini fatjar workflow successfully with ${ANSERINI_JAR}"
