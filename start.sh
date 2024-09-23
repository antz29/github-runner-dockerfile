#!/bin/bash

REPOSITORY=${REPO:?Error: REPO variable not set}
ACCESS_TOKEN=${TOKEN:?Error: TOKEN variable not set}

echo "Starting runner for repository: ${REPOSITORY}"

REG_TOKEN=$(curl -X POST \
    -H "Authorization: token ${ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/${REPOSITORY}/actions/runners/registration-token | jq -r .token)

if [ -z "$REG_TOKEN" ]; then
    echo "Error: Failed to obtain registration token"
    exit 1
fi

cd /home/docker/actions-runner

RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
LABELS=${LABELS:-self-hosted,Linux,ACI}

./config.sh --unattended --url "https://github.com/${REPOSITORY}" \
    --token "${REG_TOKEN}" --name "${RUNNER_NAME}" --labels "${LABELS}"

cleanup() {
    echo "Removing runner..."
    ./config.sh remove --unattended --token "${REG_TOKEN}"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh