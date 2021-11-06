#!/bin/bash

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -e
WD=$(dirname $0)
WD=$(cd "${WD}"; pwd)
cd "${WD}"

NAMESPACE="${NAMESPACE:-twopods-istio}"
DNS_DOMAIN=${DNS_DOMAIN:?"DNS_DOMAIN should be like istio-system.apps.ocp1.example.com"}
TMPDIR=${TMPDIR:-${WD}/tmp}
SERVER_REPLICA="${SERVER_REPLICA:-1}"
CLIENT_REPLICA="${CLIENT_REPLICA:-1}"
ISTIO_INJECT="${ISTIO_INJECT:-false}"
INTERCEPTION_MODE="${INTERCEPTION_MODE:-REDIRECT}"

mkdir -p "${TMPDIR}"

function pod_ip_range() {
    kubectl get network.config/cluster -o yaml | grep -m 1 -A 1 " clusterNetwork" | grep "-" | awk '{print  $3}'
}

function svc_ip_range() {
    kubectl  get network.config/cluster -o yaml | grep -m 1 -A 1 " serviceNetwork" | grep "-" | awk '{print  $2}'
}

function run_test() {
  helm -n "${NAMESPACE}" template \
      --set namespace="${NAMESPACE}" \
      --set excludeOutboundIPRanges=$(pod_ip_range)\
      --set includeOutboundIPRanges=$(svc_ip_range) \
      --set server.replica="${SERVER_REPLICA}" \
      --set client.replica="${CLIENT_REPLICA}" \
      --set server.inject="${ISTIO_INJECT}"  \
      --set client.inject="${ISTIO_INJECT}" \
      --set server.injectL="${LINKERD_INJECT}" \
      --set client.injectL="${LINKERD_INJECT}" \
      --set domain="${DNS_DOMAIN}" \
      --set interceptionMode="${INTERCEPTION_MODE}" \
      --set fortioImage="fortio/fortio:latest_release" \
          . > "${TMPDIR}/${NAMESPACE}.yaml"
  echo "Wrote file ${TMPDIR}/${NAMESPACE}.yaml"

  kubectl apply -n "${NAMESPACE}" -f "${TMPDIR}/${NAMESPACE}.yaml" || true
  kubectl rollout status deployment fortioclient -n "${NAMESPACE}" --timeout=5m
  kubectl rollout status deployment fortioserver -n "${NAMESPACE}" --timeout=5m
  echo "${TMPDIR}/${NAMESPACE}.yaml"
}

kubectl create ns "${NAMESPACE}" || true

run_test
