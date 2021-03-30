#!/bin/bash

# install kubectl
curl -Ls "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" --output /tmp/kubectl
sudo install /tmp/kubectl /usr/local/bin/kubectl
kubectl version --client

# install minikube
curl -Ls https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 --output /tmp/minikube-linux-amd64
sudo install /tmp/minikube-linux-amd64 /usr/local/bin/minikube
minikube version

# starting minikube
minikube start --cpus 2 --memory 4096

# enabled ingress & metrics servers
minikube addons enable ingress
minikube addons enable metrics-server

# enabled tunnel & dashboard
minikube tunnel > /dev/null &
minikube dashboard > /dev/null &

# create namespace testing
kubectl apply -f src/base/testing-ns.yaml

# create namespace litmus
kubectl apply -f src/base/litmus-ns.yaml

TESTING_NAMESPACE="testing"
LITMUS_NAMESPACE="litmus"



kubectl get pods -A 


# deployment
kubectl apply -f src/nginx/nginx-deployment.yaml --namespace="${TESTING_NAMESPACE}"

# enable hpa
kubectl apply -f src/nginx/ngix-hpa.yaml --namespace="${TESTING_NAMESPACE}"

# expose service 
kubectl expose deployment app-sample --type=LoadBalancer --port=8080  -n "${TESTING_NAMESPACE}"

# add annotate (enable chaos)
kubectl annotate deploy/app-sample litmuschaos.io/chaos="true" -n "${TESTING_NAMESPACE}"


# litmus operator & experiments
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v1.13.0.yaml -n "${LITMUS_NAMESPACE}"

kubectl apply -f https://hub.litmuschaos.io/api/chaos/1.13.0\?file\=charts/generic/experiments.yaml -n "${TESTING_NAMESPACE}"

# pod delete
kubectl apply -f src/litmus/pod-delete/pod-delete-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/pod-delete/chaos-engine-pod-delete.yaml -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-pod-delete -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"


# pod-cpu-hog
kubectl apply -f src/litmus/pod-cpu-hog/pod-cpu-hog-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/pod-cpu-hog/chaos-engine-pod-cpu-hog.yaml -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-pod-cpu-hog -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"

## pod-autoscaler
kubectl apply -f src/litmus/pod-autoscaler/pod-autoscaler-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/pod-autoscaler/chaos-engine-pod-autoscaler.yaml  -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-pod-autoscaler  -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"


## pod-network-loss
kubectl apply -f src/litmus/pod-network-loss/pod-network-loss-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/pod-network-loss/chaos-engine-pod-network-loss.yaml  -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-pod-network-loss -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"


## kill-container
kubectl apply -f src/litmus/kill-container/kill-container-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/kill-container/chaos-engine-kill-container.yaml  -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-container-kill -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"

kubectl describe chaosresult app-sample-chaos-container-kill -n "${TESTING_NAMESPACE}" 

## pod-memory-hog

kubectl apply -f src/litmus/pod-memory/pod-memory-hog-sa.yaml -n "${TESTING_NAMESPACE}"

kubectl apply -f src/litmus/pod-memory/chaos-engine-pod-memory-hog.yaml  -n "${TESTING_NAMESPACE}"

watch -n 1 kubectl get chaosresult app-sample-chaos-pod-memory-hog -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"

# install litmus portal
kubectl apply -f src/litmus/portal/portal.yaml

# kubectl apply -f src/litmus/portal.yaml
minikube service litmusportal-frontend-service -n  ${LITMUS_NAMESPACE} > /dev/null &


# monitoring
TESTING_NAMESPACE='testing'
URL_SERVICE=$(minikube service app-sample --url -n "${TESTING_NAMESPACE}")
while true; do sleep 1; curl --connect-timeout 3 ${URL_SERVICE}; echo -e ' '$(date);done

TESTING_NAMESPACE='testing'
watch -n 1 kubectl get pods -n "${TESTING_NAMESPACE}"


##########################


cd monitoring/utils

kubectl create ns monitoring

kubectl -n monitoring apply -f src/litmus/monitoring/utils/prometheus/prometheus-operator/

kubectl -n monitoring apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/node-exporter/
kubectl -n monitoring apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/kube-state-metrics/
kubectl -n monitoring apply -f src/litmus/monitoring/utils/alert-manager-with-service-monitor/
kubectl -n litmus apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/litmus-metrics/chaos-exporter/
kubectl -n litmus apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/litmus-metrics/litmus-event-router/

kubectl -n monitoring apply -f src/litmus/monitoring/utils/prometheus/prometheus-configuration/

kubectl -n monitoring apply -f src/litmus/monitoring/utils/grafana/

kubectl get svc -n monitoring


minikube service prometheus-k8s --url -n monitoring
minikube service grafana --url -n monitoring

minikube service grafana -n monitoring > /dev/null &