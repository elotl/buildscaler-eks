#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export NAME=${NAME:-buildscaler}
export NAMESPACE=${NAMESPACE:-default}
export BUILDSCALER_SERVICE_ACCOUNT_NAME=${BUILDSCALER_SERVICE_ACCOUNT_NAME:-$NAME}
export BUILDKITE_ACCESS_TOKEN_SECRET_NAME=${BUILDKITE_ACCESS_TOKEN_SECRET_NAME:-buildkite-access-token}
export BUILDKITE_AGENT_TOKEN_SECRET_NAME=${BUILDKITE_AGENT_TOKEN_SECRET_NAME:-buildkite-agent-token}
export IMAGE_REGISTRY=${IMAGE_REGISTRY:-117940112483.dkr.ecr.us-east-1.amazonaws.com/f9f9218a-2006-45bd-8906-be59ed38acca/cg-3561911556}
export BUILDSCALER_TAG=${BUILDSCALER_TAG:-1.0-latest}
export METERING_AGENT_TAG=${METERING_AGENT_TAG:-1.0-latest}

[[ -z "$BUILDKITE_ACCESS_TOKEN" ]] && {
    echo "BUILDKITE_ACCESS_TOKEN must be set to the value of a buildkite access token you have created with permissions to red builds, list agents and stop agents"
    exit 1
}

[[ -z "$BUILDKITE_AGENT_TOKEN" ]] && {
    echo "BUILDKITE_AGENT_TOKEN must be set to the value of your buildkite agent token."
    exit 1
}

[[ -z "$BUILDKITE_ORG_SLUG" ]] && {
    echo "BUILDKITE_ORG_SLUG must be set to your Buildkite orgnaization slug."
    exit 1
}

[[ -z "$BUILDSCALER_SERVICE_ACCOUNT_ROLE_ARN" ]] && {
    echo "BUILDSCALER_SERVICE_ACCOUNT_ROLE_ARN must be set to the ARN of the buildscaler IAM role created as a manual step in the README."
    exit 1
}
export BUILDSCALER_SERVICE_ACCOUNT_ROLE_ARN

export BUILDKITE_ACCESS_TOKEN_ENCODED=$(echo -n $BUILDKITE_ACCESS_TOKEN | base64)
export BUILDKITE_AGENT_TOKEN_ENCODED=$(echo -n $BUILDKITE_AGENT_TOKEN | base64)

envsubst --version > /dev/null 2>&1 || {
    echo "Missing envsubst"
    exit 1
}

env | grep BUILD

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

envsubst < "${SCRIPT_DIR}/manifests.yaml" | kubectl apply -f -
