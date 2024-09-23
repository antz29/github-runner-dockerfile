#!/bin/bash

REPOSITORY=${REPO:?Error: REPO variable not set}
APP_ID=${GITHUB_APP_ID:?Error: GITHUB_APP_ID variable not set}
INSTALLATION_ID=${GITHUB_INSTALLATION_ID:?Error: GITHUB_INSTALLATION_ID variable not set}
PRIVATE_KEY_PATH=${GITHUB_PRIVATE_KEY_PATH:?Error: GITHUB_PRIVATE_KEY_PATH variable not set}

echo "Starting runner for repository: ${REPOSITORY}"

# Generate a JWT (JSON Web Token) for GitHub App authentication
now=$(date +%s)
payload_header='{"alg":"RS256","typ":"JWT"}'
payload_claims='{"iat":'"$now"',"exp":'"$((now + 540))"',"iss":"'"$APP_ID"'"}'

base64_encode() {
  openssl base64 -in /dev/stdin | tr -d '\n' | tr -- '+/' '-_' | tr -d '='
}

header_base64=$(echo -n "$payload_header" | base64_encode)
claims_base64=$(echo -n "$payload_claims" | base64_encode)
unsigned_token="${header_base64}.${claims_base64}"
signature=$(echo -n "$unsigned_token" | openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" | base64_encode)
jwt_token="${unsigned_token}.${signature}"

# Obtain Installation Access Token
ACCESS_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer ${jwt_token}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens | jq -r .token)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    echo "Error: Failed to obtain installation access token"
    exit 1
fi

# Obtain Runner Registration Token
REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/${REPOSITORY}/actions/runners/registration-token | jq -r .token)

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" == "null" ]; then
    echo "Error: Failed to obtain runner registration token"
    exit 1
fi

cd /home/docker/actions-runner

./config.sh --unattended --url "https://github.com/${REPOSITORY}" --token "${REG_TOKEN}"

cleanup() {
    echo "Removing runner..."
    ./config.sh remove --unattended --token "${REG_TOKEN}"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh