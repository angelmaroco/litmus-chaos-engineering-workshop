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

# create namespace monitoring (prometheus + grafana)
kubectl apply -f src/base/monitoring-ns.yaml

TESTING_NAMESPACE="testing"
LITMUS_NAMESPACE="litmus"
MONITORING_NAMESPACE="monitoring"

# deployment
kubectl apply -f src/nginx/nginx-deployment.yaml --namespace="${TESTING_NAMESPACE}"

# enable hpa
kubectl apply -f src/nginx/nginx-hpa.yaml --namespace="${TESTING_NAMESPACE}"

# expose service 
kubectl expose deployment app-sample --type=LoadBalancer --port=80  -n "${TESTING_NAMESPACE}"

# litmus operator & experiments
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v1.13.0.yaml -n "${LITMUS_NAMESPACE}"

kubectl apply -f https://hub.litmuschaos.io/api/chaos/1.13.0\?file\=charts/generic/experiments.yaml -n "${TESTING_NAMESPACE}"

kubectl get chaosexperiments -n "${TESTING_NAMESPACE}"

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/prometheus/prometheus-operator/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/kube-state-metrics/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/alert-manager-with-service-monitor/

kubectl -n ${LITMUS_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/litmus-metrics/chaos-exporter/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/prometheus/prometheus-configuration/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/grafana/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/node-exporter/

# wait deployment
kubectl wait --for=condition=available --timeout=60s deployment/grafana -n ${MONITORING_NAMESPACE}
kubectl wait --for=condition=available --timeout=60s deployment/prometheus-operator -n ${MONITORING_NAMESPACE}

echo "Acceso dashboard --> $(minikube service grafana -n ${MONITORING_NAMESPACE} --url)/d/nodepodmetrics/node-and-pod-chaos-metrics?orgId=1&refresh=5s"

# add annotate (enable chaos)
kubectl annotate deploy/app-sample litmuschaos.io/chaos="true" -n "${TESTING_NAMESPACE}"

curl -L https://ftp.cixug.es/apache//jmeter/binaries/apache-jmeter-5.4.1.tgz --output /tmp/apache-jmeter.tgz
tar zxvf /tmp/apache-jmeter.tgz && mv apache-jmeter-5.4.1 apache-jmeter

# install plugins-manager
curl -L https://jmeter-plugins.org/get/ --output apache-jmeter/lib/ext/jmeter-plugins-manager-1.6.jar

# install bzm - Concurrency Thread Group
curl -L https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-casutg/2.9/jmeter-plugins-casutg-2.9.jar --output apache-jmeter/lib/ext/jmeter-plugins-casutg-2.9.jar
curl -L https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-cmn-jmeter/0.6/jmeter-plugins-cmn-jmeter-0.6.jar --output apache-jmeter/lib/jmeter-plugins-cmn-jmeter-0.6.jar
curl -L https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.2/cmdrunner-2.2.jar --output apache-jmeter/lib/cmdrunner-2.2.jar
curl -L https://repo1.maven.org/maven2/net/sf/json-lib/json-lib/2.4/json-lib-2.4.jar --output apache-jmeter/lib/json-lib-2.4-jdk15.jar


curl -L https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-graphs-basic/2.0/jmeter-plugins-graphs-basic-2.0.jar --output apache-jmeter/lib/ext/jmeter-plugins-graphs-basic-2.0.jar
curl -L https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-graphs-additional/2.0/jmeter-plugins-graphs-additional-2.0.jar --output apache-jmeter/lib/ext/jmeter-plugins-graphs-additional-2.0.jar

# Get url service
url=$(minikube service app-sample --url -n "${TESTING_NAMESPACE}")

HOST_APP_SAMPLE=$(echo ${url} | cut -d/ -f3 | cut -d: -f1)
PORT_APP_SAMPLE=$(echo ${url} | cut -d: -f3)

# install litmus portal
kubectl apply -f src/litmus/portal/portal.yaml

minikube service litmusportal-frontend-service -n  ${LITMUS_NAMESPACE} > /dev/null &



