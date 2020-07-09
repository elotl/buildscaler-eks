#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export NAME=${NAME:-buildscaler}
export NAMESPACE=${NAMESPACE:-default}
export BUILDSCALER_SERVICE_ACCOUNT_NAME=${BUILDSCALER_SERVICE_ACCOUNT_NAME:-$NAME}
export BUILDKITE_ACCESS_TOKEN_SECRET_NAME=${BUILDKITE_ACCESS_TOKEN_SECRET_NAME:-buildkite-access-token}
export BUILDKITE_AGENT_TOKEN_SECRET_NAME=${BUILDKITE_AGENT_TOKEN_SECRET_NAME:-buildkite-agent-token}
export IMAGE_REGISTRY=${REGISTRY:-689494258501.dkr.ecr.us-east-1.amazonaws.com}
export BUILDSCALER_TAG=${BUILDSCALER_TAG:-v1.0.0}
export METERING_AGENT_TAG=${METERING_AGENT_TAG:-v1.0.0}

[[ -z "$BUILDKITE_ACCESS_TOKEN" ]] && {
    echo "BUILDKITE_ACCESS_TOKEN must be set to your BUILDKITE_ACCESS_TOKEN with permissions to red builds, list and stop agents"
    exit 1
}

[[ -z "$BUILDKITE_AGENT_TOKEN" ]] && {
    echo "BUILDKITE_ACCESS_TOKEN must be set to your BUILDKITE_AGENT_TOKEN."
    exit 1
}

export BUILDKITE_ACCESS_TOKEN_ENCODED=$(echo -n $BUILDKITE_ACCESS_TOKEN | base64)
export BUILDKITE_AGENT_TOKEN_ENCODED=$(echo -n $BUILDKITE_AGENT_TOKEN | base64)

envsubst --version > /dev/null 2>&1 || {
    echo "Missing envsubst"
    exit 1
}

env | grep BUILD

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

envsubst < "${SCRIPT_DIR}/manifests.yaml" | less
