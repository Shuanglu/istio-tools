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
# shellcheck disable=SC2086
WD=$(dirname $0)
# shellcheck disable=SC2164
WD=$(cd "${WD}"; pwd)
# shellcheck disable=SC2164
cd "${WD}"

NAMESPACE="${NAMESPACE:-twopods}"
LOAD_GEN_TYPE="${LOAD_GEN_TYPE:-fortio}"
DNS_DOMAIN=${DNS_DOMAIN:?"DNS_DOMAIN should be like v104.qualistio.org or local"}
DNS_POD="${DNS_POD:-kube-dns}"
DNS_SVC="${DNS_SVC:-kube-dns}"
TMPDIR=${TMPDIR:-${WD}/tmp}
RBAC_ENABLED="false"
SERVER_REPLICA="${SERVER_REPLICA:-1}"
CLIENT_REPLICA="${CLIENT_REPLICA:-1}"
ISTIO_INJECT="${ISTIO_INJECT:-false}"
declare -p PODLABELS
declare -p DEPLOYLABELS
declare -p PODANNOTATIONS
declare -p DEPLOYANNOTATIONS
declare -p TUBIANNOTATIONS
INTERCEPTION_MODE="${INTERCEPTION_MODE:-REDIRECT}"
FORTIO_VERSION="${FORTIO_VERSION:-latest_release}"
TUBIMESH="${TUBIMESH}"
ISTIO_MTLS="${ISTIO_MTLS}"
PROXY_RESOURCE_REQUEST="${PROXY_RESOURCE_REQUEST}"
APPRESOURCES1="${APPRESOURCES1}"
echo "linkerd inject is ${LINKERD_INJECT}"

mkdir -p "${TMPDIR}/kustomization"

# Get pod ip range, there must be a better way, but this works.
function pod_ip_range() {
    kubectl get pods --namespace kube-system -o wide | grep "${DNS_POD}" | awk '{print $6}'|head -1 | awk -F '.' '{printf "%s.%s.0.0/16\n", $1, $2}'
}

function svc_ip_range() {
    kubectl -n kube-system get svc "${DNS_SVC}" --no-headers | awk '{print $3}' | awk -F '.' '{printf "%s.%s.0.0/16\n", $1, $2}'
}

function run_test() {
  # shellcheck disable=SC2046
  if [[ "$PODLABELS" != "" ]]; then
    for PODLABEL in ${PODLABELS[@]}; 
    do 
        TMP="--set-string podlabel.$PODLABEL"
        HELMPODLABELS=$HELMPODLABELS" "$TMP
    done
  fi
  if [[ "$PODANNOTATIONS" != "" ]]; then
    for PODANNOTATION in ${PODANNOTATIONS[@]};
    do
        TMP="--set-string podannotation.$PODANNOTATION"
        HEMPODANNOTATION=$HEMPODANNOTATION" "$TMP
    done
  fi
  if [[ "$DEPLOYLABELS" != "" ]]; then
    for DEPLOYLABEL in ${DEPLOYLABELS[@]}; 
    do 
        TMP="--set-string deploylabel.$DEPLOYLABEL"
        HELMDEPLOYLABELS=$HELMDEPLOYLABELS" "$TMP
    done
  fi
  if [[ "$DEPLOYANNOTATIONS" != "" ]]; then
    for DEPLOYANNOTATION in ${DEPLOYANNOTATIONS[@]}; 
    do 
        TMP="--set-string deployannotation.$DEPLOYANNOTATION"
        HELMANNOTATIONS=$HELMANNOTATIONS" "$TMP
    done
  fi
  if [[ "$TUBIMESH" != "" ]]; then 
    HELMCLIENTTUBIANNOTATIONS="--set-string tubiclientannotation.${TUBIANNOTATIONS[0]}"
    HELMSERVERTUBIANNOTATIONS="--set-string tubiserverannotation.${TUBIANNOTATIONS[1]}"
  fi
  helm -n "${NAMESPACE}" template \
    --set rbac.enabled="${RBAC_ENABLED}" \
    --set namespace="${NAMESPACE}" \
    --set loadGenType="${LOAD_GEN_TYPE}" \
    --set server.replica="${SERVER_REPLICA}" \
    --set client.replica="${CLIENT_REPLICA}" \
    --set domain="${DNS_DOMAIN}" \
    --set fortioImage="fortio/fortio:${FORTIO_VERSION}" \
    ${HELMPODLABELS} \
    ${HELMDEPLOYLABELS} \
    ${HEMPODANNOTATION} \
    ${HELMANNOTATIONS} \
    ${HELMTUBIANNOTATIONS} \
    ${HELMCLIENTTUBIANNOTATIONS} \
    ${HELMSERVERTUBIANNOTATIONS} \
    --set istioMtls="${ISTIO_MTLS}" \
    --set proxyResourceRequest="${PROXY_RESOURCE_REQUEST}" \
    --set appresources1="${APPRESOURCES1}" \
        . > "${TMPDIR}/kustomization/${NAMESPACE}.yaml"

  echo "Wrote file ${TMPDIR}/kustomization/${NAMESPACE}.yaml"
  cp -R ../../../kustomization "${TMPDIR}"/
    if [[ "$TUBIMESH" == "true" ]]; then 
    sed -e "s/NAMESPACE/${NAMESPACE}/g"  ../../../kustomization/kustomization.yaml.tubi > "${TMPDIR}"/kustomization/kustomization.yaml
  else
    sed -e "s/NAMESPACE/${NAMESPACE}/g"  ../../../kustomization/kustomization.yaml > "${TMPDIR}"/kustomization/kustomization.yaml
  fi

  # remove stdio rules
  kustomize build "${TMPDIR}/kustomization" | kubectl apply -n "${NAMESPACE}" -f - || true
  # remove stdio rules
  #kubectl apply -n "${NAMESPACE}" -f "${TMPDIR}/${NAMESPACE}.yaml" || true
  kubectl rollout status deployment fortioclient -n "${NAMESPACE}" --timeout=5m
  kubectl rollout status deployment fortioserver -n "${NAMESPACE}" --timeout=5m
  echo "${TMPDIR}/${NAMESPACE}.yaml"
  rm -rf "${TMPDIR}/kustomization"
  rm -rf "${TMPDIR}/fortio*"
}

for ((i=1; i<=$#; i++)); do
    case ${!i} in
        -r|--rbac) ((i++)); RBAC_ENABLED="true"
        continue
        ;;
    esac
done

kubectl create ns "${NAMESPACE}" || true

#if [[ "$ISTIO_INJECT" == "true" ]]
#then
#  kubectl label namespace "${NAMESPACE}" istio-injection=enabled --overwrite || true
#fi

#if [[ "$LINKERD_INJECT" == "enabled" ]]
#then
#  kubectl annotate namespace "${NAMESPACE}" linkerd.io/inject=enabled || true
#fi

run_test
