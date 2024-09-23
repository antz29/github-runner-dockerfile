#!/bin/bash

# Required environment variables
REPOSITORY=${REPO:?Error: REPO variable not set}
APP_ID=${GITHUB_APP_ID:?Error: GITHUB_APP_ID variable not set}
INSTALLATION_ID=${GITHUB_INSTALLATION_ID:?Error: GITHUB_INSTALLATION_ID variable not set}
KEY_VAULT_NAME=${KEY_VAULT_NAME:?Error: KEY_VAULT_NAME variable not set}
SECRET_NAME=${SECRET_NAME:-GitHubAppPrivateKey}

echo "Starting runner for repository: ${REPOSITORY}"

# Function to base64 encode without line wrapping
base64_encode() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# Function to obtain an access token for Azure Key Vault
get_access_token() {
  curl -s 'http://169.254.169.254/metadata/identity/oauth2/token' \
    -H 'Metadata: true' \
    --data-urlencode 'api-version=2018-02-01' \
    --data-urlencode 'resource=https://vault.azure.net' | jq -r '.access_token'
}

# Obtain an access token for Azure Key Vault
ACCESS_TOKEN=$(get_access_token)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: Unable to obtain access token for Azure Key Vault"
  exit 1
fi

# Retrieve the private key from Azure Key Vault
PRIVATE_KEY=$(curl -s \
  "https://${KEY_VAULT_NAME}.vault.azure.net/secrets/${SECRET_NAME}?api-version=7.0" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.value')

if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: Unable to retrieve private key from Azure Key Vault"
  exit 1
fi

# Generate JWT for GitHub App authentication
now=$(date +%s)
payload_header='{"alg":"RS256","typ":"JWT"}'
payload_claims="{\"iat\":${now},\"exp\":$((now + 540)),\"iss\":\"${APP_ID}\"}"

header_base64=$(echo -n "$payload_header" | base64_encode)
claims_base64=$(echo -n "$payload_claims" | base64_encode)
unsigned_token="${header_base64}.${claims_base64}"

# Sign the JWT using the private key
signature=$(printf '%s' "$unsigned_token" | openssl dgst -sha256 -sign <(echo "$PRIVATE_KEY") | base64_encode)
jwt_token="${unsigned_token}.${signature}"

# Obtain Installation Access Token
GITHUB_ACCESS_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer ${jwt_token}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens | jq -r .token)

if [ -z "$GITHUB_ACCESS_TOKEN" ] || [ "$GITHUB_ACCESS_TOKEN" == "null" ]; then
  echo "Error: Failed to obtain installation access token"
  exit 1
fi

# Obtain Runner Registration Token
REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/${REPOSITORY}/actions/runners/registration-token | jq -r .token)

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" == "null" ]; then
  echo "Error: Failed to obtain runner registration token"
  exit 1
fi

cd /home/docker/actions-runner

# Configure the runner
./config.sh --unattended --url "https://github.com/${REPOSITORY}" --token "${REG_TOKEN}"

# Define cleanup function
cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token "${REG_TOKEN}"
}

# Set trap for termination signals
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Run the runner
./run.sh