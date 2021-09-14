#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

NAMESERVERS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | xargs)
patch=$(kubectl get configmap coredns \
                --namespace kube-system \
                --template='{{.data.Corefile}}' \
            | sed "s/forward.*/forward . $NAMESERVERS/g" \
            | tr '\n' '^' \
            | xargs -0 printf '{"data": {"Corefile":"%s"}}' \
            | sed -E 's%\^%\\n%g')

mkdir -p $SCRIPT_DIRECTORY/volumes/test-management-cluster

k3d cluster delete test-management-cluster
k3d cluster create test-management-cluster \
    --config "$SCRIPT_DIRECTORY/config.yaml" \
    --volume "$SCRIPT_DIRECTORY/volumes/test-management-cluster:/var/lib/rancher/k3s/storage/"

kubectl patch configmap coredns -n kube-system -p="$patch"

flux install \
  --watch-all-namespaces=true \
  --namespace flux-system \
  --version=v0.17.0 \
  --export | kubectl apply -f -

mkdir -p $SCRIPT_DIRECTORY/volumes/test-cluster

k3d cluster delete test-cluster
k3d cluster create test-cluster \
    --config "$SCRIPT_DIRECTORY/config.yaml" \
    --volume "$SCRIPT_DIRECTORY/volumes/test-cluster:/var/lib/rancher/k3s/storage/"

kubectl patch configmap coredns -n kube-system -p="$patch"

kubectl config use-context k3d-test-management-cluster

k3d kubeconfig get test-cluster | sed 's/0.0.0.0/'"$HOSTNAME.my.local.tld"'/' > ./kubeconfig

kubectl create secret generic kubeconfig-test-cluster \
        --namespace flux-system \
        --from-file=value=./kubeconfig

rm ./kubeconfig

kubectl apply -f test.yaml
