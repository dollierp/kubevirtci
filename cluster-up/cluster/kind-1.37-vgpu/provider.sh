#!/bin/bash

# This file is part of the KubeVirt project
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright the KubeVirt Authors.

set -e

DEFAULT_CLUSTER_NAME="vgpu"
DEFAULT_HOST_PORT=5000
ALTERNATE_HOST_PORT=5001
export CLUSTER_NAME=${CLUSTER_NAME:-${DEFAULT_CLUSTER_NAME}}

if [[ ${CLUSTER_NAME} == ${DEFAULT_CLUSTER_NAME} ]]; then
  export HOST_PORT=${DEFAULT_HOST_PORT}
else
  export HOST_PORT=${ALTERNATE_HOST_PORT}
fi

function set_kind_params() {
  version=$(cat "${KUBEVIRTCI_PATH}/cluster/${KUBEVIRT_PROVIDER}"/version)
  export KIND_VERSION="${KIND_VERSION:-$version}"

  image=$(cat "${KUBEVIRTCI_PATH}/cluster/${KUBEVIRT_PROVIDER}"/image)
  export KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-$image}"
}

function configure_registry_proxy() {
  [[ "${CI}" != "true" ]] && return

  echo "Configuring cluster nodes to work with CI mirror-proxy..."

  local -r ci_proxy_hostname="docker-mirror-proxy.kubevirt-prow.svc"
  local -r kind_binary_path="${KUBEVIRTCI_CONFIG_PATH}/${KUBEVIRT_PROVIDER}/.kind"
  local -r configure_registry_proxy_script="${KUBEVIRTCI_PATH}/cluster/kind/configure-registry-proxy.sh"

  KIND_BIN="${kind_binary_path}" PROXY_HOSTNAME="${ci_proxy_hostname}" ${configure_registry_proxy_script}
}

function up() {
  # print hardware info for easier debugging based on logs
  echo 'Available cards'
  ${CRI_BIN} run --rm --cap-add=SYS_RAWIO quay.io/phoracek/lspci@sha256:0f3cacf7098202ef284308c64e3fc0ba441871a846022bb87d65ff130c79adb1 sh -c "lspci -k | grep -EA2 'VGA|3D'"
  echo

  cp "${KIND_MANIFESTS_DIR}"/kind.yaml "${KUBEVIRTCI_CONFIG_PATH}/${KUBEVIRT_PROVIDER}"/kind.yaml
  _add_extra_mounts
  kind_up

  configure_registry_proxy

  "${KUBEVIRTCI_PATH}/cluster/${KUBEVIRT_PROVIDER}"/config_vgpu_cluster.sh

  echo "${KUBEVIRT_PROVIDER} cluster '${CLUSTER_NAME}' is ready"
}

set_kind_params

source "${KUBEVIRTCI_PATH}"/cluster/kind/common.sh
