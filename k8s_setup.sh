#!/usr/bin/env bash

kubeconfig="./.vagrant/provisioners/ansible/inventory/artifacts/admin.conf"

function check_is_kubeconfig_exist() {
  if ! [[ -f "${kubeconfig}" ]]; then
    echo "Fatal! There is no .vagrant/provisioners/ansible/inventory/artifacts/admin.conf in ${PWD}. Exit." >&2; exit 1;
  fi
}

function add_and_update_helm_repos() {
  helm --kubeconfig "${kubeconfig}" repo add argo https://argoproj.github.io/argo-helm;
  helm --kubeconfig "${kubeconfig}" repo add jetstack https://charts.jetstack.io;
  helm --kubeconfig "${kubeconfig}" repo add istio https://istio-release.storage.googleapis.com/charts;
  helm --kubeconfig "${kubeconfig}" repo add metallb https://metallb.github.io/metallb;
  helm --kubeconfig "${kubeconfig}" repo update argo jetstack istio;
}

function upgrade_install_metallb() {
  echo "Installing metallb. Please wait...";
  helm --kubeconfig "${kubeconfig}" \
  upgrade --install metallb --create-namespace \
  --namespace metallb-system --version 0.14.3 \
  metallb/metallb
}

function upgrade_install_cert_manager() {
  echo "Installing cert-manager. Please wait...";
  helm --kubeconfig "${kubeconfig}" \
  upgrade --install cert-manager --create-namespace \
  jetstack/cert-manager -f ./infra/values/cert-manager/cert-manager.yaml \
  --namespace cert-manager --version v1.14.3  || \
  { echo "Failure of argocd installation. Aborting."; exit 1; }
}

function upgrade_install_istio() {
  echo "Installing istio components. Please wait...";
  helm --kubeconfig "${kubeconfig}" upgrade --install istio-base \
    istio/base -n istio-system --create-namespace --version 1.20.3 || \
    { echo "Failure of istio-base installation. Aborting."; exit 1; }
  helm --kubeconfig "${kubeconfig}" upgrade --install istiod \
    istio/istiod -n istio-system --version 1.20.3 || \
    { echo "Failure of Istiod installation. Aborting."; exit 1; }
  helm --kubeconfig "${kubeconfig}" upgrade --install istio-ingressgateway \
    istio/gateway -n istio-system --version 1.20.3 || \
    { echo "Failure of istio-ingressgateway installation. Aborting."; exit 1; }
}

function upgrade_install_argocd() {
  echo "Installing argocd. Please wait...";
  helm --kubeconfig "${kubeconfig}" upgrade \
    --install argocd argo/argo-cd --wait \
    --create-namespace -n argocd \
    -f ./infra/values/argocd/argocd.yaml \
    --version 6.6.0 || { echo "Failure of argocd installation. Aborting."; exit 1; }
}

function apply_extra_manifests() {
  echo "Apply extra manifests. Please wait...";
  helm template --show-only templates/extra-manifests.yaml extras ./infra \
  -f infra/home-lab-values.yaml | kubectl --kubeconfig "${kubeconfig}" apply -f -
}

function main() {
    check_is_kubeconfig_exist
    upgrade_install_metallb
    add_and_update_helm_repos
    upgrade_install_cert_manager
    upgrade_install_istio
    upgrade_install_argocd
    apply_extra_manifests
}

main
