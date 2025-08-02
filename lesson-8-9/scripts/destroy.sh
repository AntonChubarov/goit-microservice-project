#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo ">> Destroying Terraform-managed resources ..."
terraform destroy -auto-approve

echo "Done."
