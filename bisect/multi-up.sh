#!/bin/bash

set -u -o pipefail

SELF_DIR=$(dirname "$(readlink -f "$0")")
TOP_DIR=${SELF_DIR%/*}

export KUBEVIRTCI_TAG=${KUBEVIRTCI_TAG:-2605121213-3c9d7dff}

for ((TRY=100; TRY>0; TRY--)); do
    sudo make cluster-up KUBEVIRTCI_TAG="${KUBEVIRTCI_TAG}" || ((FAILURE++))
    sudo make cluster-down KUBEVIRTCI_TAG="${KUBEVIRTCI_TAG}"
done

exit
