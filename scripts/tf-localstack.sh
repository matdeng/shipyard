#!/usr/bin/env bash
# Apply the Terraform code against LocalStack, check the outputs, then destroy.
# Usage: scripts/tf-localstack.sh   (needs: docker, terraform, ssh-keygen)
set -euo pipefail
cd "$(dirname "$0")/.."
ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4567}"
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; exit 1; }

docker compose -f docker-compose.localstack.yml up -d --wait >/dev/null
pass "LocalStack up at $ENDPOINT"

# Work in a scratch copy so the real terraform/ dir (state, inventory) is untouched.
WORK=$(mktemp -d)
trap 'terraform -chdir="$WORK/terraform" destroy -auto-approve -input=false >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/terraform" "$WORK/ansible"
cp terraform/*.tf "$WORK/terraform/"
cp terraform/localstack/variables.tf "$WORK/terraform/localstack_variables.tf"
cp terraform/localstack/provider_override.tf "$WORK/terraform/localstack_override.tf"
ssh-keygen -q -t ed25519 -N "" -f "$WORK/key"

TF=(terraform -chdir="$WORK/terraform")
VARS=(-var "my_ip_cidr=203.0.113.7/32" -var "ssh_public_key_path=$WORK/key.pub"
      -var "ssh_private_key_path=$WORK/key" -var "localstack_endpoint=$ENDPOINT")

"${TF[@]}" init -input=false >/dev/null && pass "terraform init" || fail "terraform init"
"${TF[@]}" apply -auto-approve -input=false "${VARS[@]}" >/dev/null && pass "terraform apply" || fail "terraform apply"

ip=$("${TF[@]}" output -raw public_ip)
[[ -n "$ip" ]]                                                   && pass "public_ip output: $ip" || fail "empty public_ip"
grep -q "ansible_host=$ip" "$WORK/ansible/inventory.ini"         && pass "ansible inventory written" || fail "inventory missing"
"${TF[@]}" output -raw app_url | grep -q "^http://$ip"           && pass "app_url output" || fail "app_url"

# The validation rule must reject 0.0.0.0/0.
if "${TF[@]}" plan -input=false "${VARS[@]}" -var "my_ip_cidr=0.0.0.0/0" >/dev/null 2>&1; then
  fail "0.0.0.0/0 was accepted for my_ip_cidr"
else pass "my_ip_cidr rejects 0.0.0.0/0"; fi
echo "All Terraform checks passed against LocalStack."
