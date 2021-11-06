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

WD=$(dirname "$0")
WD=$(cd "$WD"; pwd)
ROOT=$(dirname "$WD")

set -e
set -u
set -x

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Istio performance test related Env vars
export NAMESPACE=${NAMESPACE:-'twopods-istio'}
export ISTIO_INJECT=${ISTIO_INJECT:-true}
export DNS_DOMAIN="istio-system.apps.ocp1.example.com"
export FORTIO_CLIENT_URL=""

export TRIALRUN=${TRIALRUN:-"False"}

OUTPUT_DIR="/tmp/benchmark"
mkdir -p "${OUTPUT_DIR}"

# Step x: setup Istio performance test
pushd "${WD}"
export ISTIO_INJECT="true"
#./setup_test.sh
popd

# Step x: install pipenv & dependencies
cd "${WD}"
pip3 install pipenv
pipenv install

# Step x: config fortio and prometheus connection
function config_fortio_and_prometheus_connection() {
    export FORTIO_CLIENT_URL=http://fortioclient.istio-system.apps.ocp1.example.com
    export PROMETHEUS_URL=https://prometheus-k8s-openshift-monitoring.apps.ocp1.example.com
    export PROMETHEUS_TOKEN=$(oc whoami -t)
}

config_fortio_and_prometheus_connection

function read_perf_test_conf() {
  perf_test_conf="${1}"
  while IFS="=" read -r key value; do
    case "$key" in
      '#'*) ;;
      *)
        export ${key}="${value}"
    esac
  done < "${perf_test_conf}"
}

function collect_metrics() {
  # shellcheck disable=SC2155
  STAMP=$(date '+%Y%m%d%H%M%S')_$(echo $RANDOM)
  export CSV_OUTPUT="$(mktemp /tmp/benchmark_${STAMP}.csv)"
  echo $CSV_OUTPUT
  pipenv run python3 fortio.py ${FORTIO_CLIENT_URL} --csv_output="$CSV_OUTPUT" \
   --prometheus=${PROMETHEUS_URL} --prometheus_token=${PROMETHEUS_TOKEN}\
   --csv StartTime,ActualDuration,Labels,NumThreads,ActualQPS,p50,p90,p99,p999,cpu_mili_avg_istio_proxy_fortioclient,\
cpu_mili_avg_istio_proxy_fortioserver,cpu_mili_avg_istio_proxy_istio-ingressgateway,mem_Mi_avg_istio_proxy_fortioclient,\
mem_Mi_avg_istio_proxy_fortioserver,mem_Mi_avg_istio_proxy_istio-ingressgateway

  cp "${CSV_OUTPUT}" "${OUTPUT_DIR}"
}

function run_benchmark_test() {
  pushd "${WD}/runner"
  CONFIG_FILE="${1}"
  pipenv run python3 runner.py --config_file "${CONFIG_FILE}"

  if [[ "${TRIALRUN}" == "False" ]]; then
    collect_metrics
  fi

  popd
}

# Start run perf test
echo "Start to run perf benchmark test"
CONFIG_DIR="${WD}/configs/istio"
read_perf_test_conf "${WD}/configs/run_perf_test.conf"

for dir in "${CONFIG_DIR}"/*; do
    config_name="$(basename "${dir}")"
    # skip the test config which is disabled for running
    if ! ${!config_name:-false}; then
        continue
    fi

    pushd "${dir}"

    # Run test and collect data
    if [[ -e "./cpu_mem.yaml" ]]; then
       run_benchmark_test "${dir}/cpu_mem.yaml"
    fi

    if [[ -e "./latency.yaml" ]]; then
       run_benchmark_test "${dir}/latency.yaml"
    fi

    # restart proxy after each group
    #kubectl exec -n "${NAMESPACE}" "${FORTIO_CLIENT_POD}" -c istio-proxy -- curl http://localhost:15000/quitquitquit -X POST
    #kubectl exec -n "${NAMESPACE}" "${FORTIO_SERVER_POD}" -c istio-proxy -- curl http://localhost:15000/quitquitquit -X POST

    popd
done

echo "Istio performance benchmark test is done!"
