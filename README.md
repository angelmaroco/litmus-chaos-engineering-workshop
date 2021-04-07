# **Chaos Engineering sobre Kubernetes con Litmus**

![litmus logo](./docs/img/cloud-native-way.png)

- [**Chaos Engineering sobre Kubernetes con Litmus**](#chaos-engineering-sobre-kubernetes-con-litmus)
  - [**Sobre *Chaos Engineering***](#sobre-chaos-engineering)
  - [**Componentes Litmus**](#componentes-litmus)
  - [**Workshop**](#workshop)
    - [**Preparación de consola**](#preparación-de-consola)
    - [**Clonación de repositorio**](#clonación-de-repositorio)
    - [**Creación de entorno de pruebas K8s con minikube**](#creación-de-entorno-de-pruebas-k8s-con-minikube)
    - [**Creación de namespaces K8s**](#creación-de-namespaces-k8s)
    - [**Despliegue de aplicación de test**](#despliegue-de-aplicación-de-test)
    - [**Instalación *Chaos Experiments***](#instalación-chaos-experiments)
    - [**Despliegue servicios monitorización: Prometheus + Grafana**](#despliegue-servicios-monitorización-prometheus--grafana)
    - [**Creación de anotación "litmuschaos"**](#creación-de-anotación-litmuschaos)
    - [**Detalle componetes de un experimento**](#detalle-componetes-de-un-experimento)
      - [**Service Account, Role y RoleBinding**](#service-account-role-y-rolebinding)
      - [**Definición ChaosEngine**](#definición-chaosengine)
        - [**Especificaciones generales**](#especificaciones-generales)
        - [**Especificaciones de componentes**](#especificaciones-de-componentes)
        - [**Especificaciones de pruebas**](#especificaciones-de-pruebas)
    - [**Ejecución de experimentos**](#ejecución-de-experimentos)
      - [**Container Kill**](#container-kill)
      - [**Pod autoscaler**](#pod-autoscaler)
      - [**Pod CPU Hog**](#pod-cpu-hog)
      - [**Extra - Otros experimentos**](#extra---otros-experimentos)
    - [**Planificación de experimentos**](#planificación-de-experimentos)
  - [**LitmusChaos + *Load Test Performance* con Jmeter**](#litmuschaos--load-test-performance-con-jmeter)
  - [**Litmus UI Portal**](#litmus-ui-portal)
  - [**Guía Litmus para desarrolladores**](#guía-litmus-para-desarrolladores)
  - [***Chaos Engineering* en despliegue Continuo**](#chaos-engineering-en-despliegue-continuo)
  - [**Consideraciones finales**](#consideraciones-finales)
  - [**Referencias**](#referencias)
  - [**Licencia**](#licencia)
  - [**Autor**](#autor)
  

## **Sobre *Chaos Engineering***

## **Componentes Litmus**

* **ChaosEngine:**
* **ChaosExperiment**
* **ChaosSchedule**
* **ChaosResult**
* **Litmus Probes**

## **Workshop**

### **Preparación de consola**

Recomendamos abrir una consola y crear 4 paneles:

1. Panel principal (ejecutaremos todo el contenido del workshop)
2. Monitorización de la aplicación de test
3. Monitorización de pods
4. Monitorización de eventos
   
![Console tabs](./docs/img/console-tabs.png)

### **Clonación de repositorio**

```bash
git clone git@github.com:angelmaroco/litmus-chaos-engineering-workshop.git
cd litmus-chaos-engineering-workshop
```

### **Creación de entorno de pruebas K8s con minikube**

```bash
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
```

### **Creación de namespaces K8s**
```bash
# create namespace testing
kubectl apply -f src/base/testing-ns.yaml

# create namespace litmus
kubectl apply -f src/base/litmus-ns.yaml

# create namespace monitoring (prometheus + grafana)
kubectl apply -f src/base/monitoring-ns.yaml

TESTING_NAMESPACE="testing"
LITMUS_NAMESPACE="litmus"
MONITORING_NAMESPACE="monitoring"
```

### **Despliegue de aplicación de test**

Desplegamos una aplicación de test para poder ejecutar los experimentos de litmus.
* **nginx-deployment.yaml**: creación de despliegue "app-sample", con recursos de cpu/memoria "limits"/"request" y configuración de "readinessProbe". Exponemos el servicio en el puerto 8080 a través de un balanceador. 
* **nginx-hpa.yaml**: creación de *Horizontal Pod Autoscaler* (min 2 réplicas / max 10 réplicas)

```bash
# deployment
kubectl apply -f src/nginx/nginx-deployment.yaml --namespace="${TESTING_NAMESPACE}"

# enable hpa
kubectl apply -f src/nginx/nginx-hpa.yaml --namespace="${TESTING_NAMESPACE}"

# expose service 
kubectl expose deployment app-sample --type=LoadBalancer --port=80  -n "${TESTING_NAMESPACE}"

# wait deployment
kubectl wait --for=condition=available --timeout=60s deployment/app-sample -n "${TESTING_NAMESPACE}"

# get pods
kubectl get pods -n "${TESTING_NAMESPACE}"

#-----------------------------------------

NAME                          READY   STATUS    RESTARTS   AGE
app-sample-7ff489dbd5-82ppw   1/1     Running   0          45m
app-sample-7ff489dbd5-jg9vh   1/1     Running   0          45m
```

:information_source: En **PANEL 2** ejecutar: 
```bash
TESTING_NAMESPACE='testing'
URL_SERVICE=$(minikube service app-sample --url -n "${TESTING_NAMESPACE}")
while true; do sleep 5; curl --connect-timeout 2 -s -o /dev/null -w "Response code %{http_code}"  ${URL_SERVICE}; echo -e ' - '$(date);done

```

:information_source: En **PANEL 3** ejecutar: 
```bash
TESTING_NAMESPACE='testing'
watch -n 1 kubectl get pods -n "${TESTING_NAMESPACE}"
```

:information_source: En **PANEL 4** ejecutar: 
```bash
kubectl get events -A -w
```

### **Instalación *Chaos Experiments***

```bash
# litmus operator & experiments
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v1.13.0.yaml -n "${LITMUS_NAMESPACE}"

kubectl apply -f https://hub.litmuschaos.io/api/chaos/1.13.0\?file\=charts/generic/experiments.yaml -n "${TESTING_NAMESPACE}"
```

```bash
kubectl get chaosexperiments -n "${TESTING_NAMESPACE}"

# ----------------------------------------------------

NAME                      AGE
container-kill            6s
disk-fill                 6s
disk-loss                 6s
docker-service-kill       6s
k8-pod-delete             6s
k8-service-kill           6s
kubelet-service-kill      6s
node-cpu-hog              6s
node-drain                6s
node-io-stress            6s
node-memory-hog           6s
node-poweroff             6s
node-restart              6s
node-taint                6s
pod-autoscaler            6s
pod-cpu-hog               6s
pod-delete                6s
pod-io-stress             6s
pod-memory-hog            6s
pod-network-corruption    6s
pod-network-duplication   6s
pod-network-latency       6s
pod-network-loss          6s
```

### **Despliegue servicios monitorización: Prometheus + Grafana**

Litmus permite exportar las métricas de los experimentos a Prometheus a través de *chaos-exporter*.

```bash
kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/prometheus/prometheus-operator/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/node-exporter/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/kube-state-metrics/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/alert-manager-with-service-monitor/

kubectl -n ${LITMUS_NAMESPACE} apply -f src/litmus/monitoring/utils/metrics-exporters-with-service-monitors/litmus-metrics/chaos-exporter/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/prometheus/prometheus-configuration/

kubectl -n ${MONITORING_NAMESPACE} apply -f src/litmus/monitoring/utils/grafana/

# wait deployment
kubectl wait --for=condition=available --timeout=60s deployment/grafana -n ${MONITORING_NAMESPACE}
kubectl wait --for=condition=available --timeout=60s deployment/prometheus-operator -n ${MONITORING_NAMESPACE}

echo "Acceso dashboard --> $(minikube service grafana -n ${MONITORING_NAMESPACE} --url)/d/nodepodmetrics/node-and-pod-chaos-metrics?orgId=1&refresh=5s"
```

Para este workshop hemos personalizado un dashboard de grafana donde visualizaremos:

- Timelime de experimentos ejecutados
- 4 gráficas tipo "Gauge" con número de total de experimentos, estado Pass, estado Fail y estado Awaited.
- Consumo de CPU nivel nodo
- Consumo de CPU a nivel POD (app-sample)
- Consumo de memoria nivel nodo
- Consumo de memoria a nivel POD (app-sample)
- Tráfico red (IN/OUT) nivel nodo
- Tráfico red (IN/OUT) nivel POD (app-sample)

Datos acceso grafana: 
- usuario: admin
- password: admin

![others-exp](./docs/img/grafana-main.png)

### **Creación de anotación "litmuschaos"**

Para habilitar la ejecución de experimentos contra nuestro deployment, necesitamos añadir la anotación *litmuschaos.io/chaos="true"*. Como veremos más adelante, todos los experimentos tienen la propiedad *annotationCheck: "true"*.

```bash
# add annotate (enable chaos)
kubectl annotate deploy/app-sample litmuschaos.io/chaos="true" -n "${TESTING_NAMESPACE}"
``` 

```bash
kubectl describe deploy/app-sample -n "${TESTING_NAMESPACE}"

# -----------------------------------------------------------

Name:                   app-sample
Namespace:              testing
CreationTimestamp:      Mon, 29 Mar 2021 09:35:53 +0200
Labels:                 app=app-sample
                        app.kubernetes.io/name=app-sample
Annotations:            deployment.kubernetes.io/revision: 1
                        litmuschaos.io/chaos: true # <-- HABILITAMOS EXPERIMENTOS
Selector:               app.kubernetes.io/name=app-sample
Replicas:               2 desired | 2 updated | 2 total | 2 available | 0 unavailable
StrategyType:           RollingUpdate
```

### **Detalle componetes de un experimento**

#### **Service Account, Role y RoleBinding**

Cada experimento debe tener asociado un ServiceAccount, un Role para definir permisos y un RoleBinding para relacionar el ServiceAccount/Role.

Podéis encontrar todas las definiciones dentro de *src/litmus/nombre-experimento/nombre-experimento-sa.yaml*

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: container-kill-sa
  namespace: testing
  labels:
    name: container-kill-sa
    app.kubernetes.io/part-of: litmus
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: container-kill-sa
  namespace: testing
  labels:
    name: container-kill-sa
    app.kubernetes.io/part-of: litmus
rules:
  - apiGroups: [""]
    resources:
      ["pods", "pods/exec", "pods/log", "events", "replicationcontrollers"]
    verbs:
      ["create", "list", "get", "patch", "update", "delete", "deletecollection"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "list", "get", "delete", "deletecollection"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["list", "get"]
  - apiGroups: ["apps.openshift.io"]
    resources: ["deploymentconfigs"]
    verbs: ["list", "get"]
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts"]
    verbs: ["list", "get"]
  - apiGroups: ["litmuschaos.io"]
    resources: ["chaosengines", "chaosexperiments", "chaosresults"]
    verbs: ["create", "list", "get", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: container-kill-sa
  namespace: testing
  labels:
    name: container-kill-sa
    app.kubernetes.io/part-of: litmus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: container-kill-sa
subjects:
  - kind: ServiceAccount
    name: container-kill-sa
    namespace: testing
```

#### **Definición ChaosEngine**

Para facilitar la comprensión, hemos dividido en 3 secciones el contenido de un experimiento. Podéis encontrar todas las definiciones dentro de *src/litmus/nombre-experimento/chaos-engine-*.yaml*


##### **Especificaciones generales**

En esta sección especificaremos atributos comunes a todos los experimentos. Para este workshop, debido a que estamos realizando los experimentos contra un único deployment, el único atributo que cambiará entre experimentos es "chaosServiceAccount".

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: app-sample-chaos # Nombre del chaos-engine
  namespace: testing     # Namespace de testing
spec:
  annotationCheck: "true" # Hemos creado una anotación en nuestro deployment app-sample. Con la propiedad marcada a "true" indicamos que aplicarmeos el experimento a este despliegue.

  engineState: "active"   # Activación/desactivación de experimento

  appinfo:                # En esta sección proporcionamos la información de nuestro deployment.
    appns: "testing"      # Namespace donde se localiza
    applabel: "app.kubernetes.io/name=app-sample" # Etiqueta asociada a nuestro deployment
    appkind: "deployment" # Tipo de recurso (sólo admite deployment, lo que afectará a todos los pods)

  chaosServiceAccount: container-kill-sa # Nombre del service account (creado en el paso anterior)
  monitoring: true       # si queremos activar la monitorización (prometheus o similares)
  jobCleanUpPolicy: "delete" # Permite controlar la limpieza de recursos tras la ejecución. Especificar "retain" para debug.
```

##### **Especificaciones de componentes**
En esta sección definiremos las variables de entorno propias de cada experimento. Las variables "CHAOS_INTERVAL" y "TOTAL_CHAOS_DURATION" son comunes a todos los experimentos.
```yaml
  experiments:
    - name: container-kill # Nombre del experimento
      spec:
        components:
          env:
            # Intervalo (segundos) por cada iteración
            - name: CHAOS_INTERVAL
              value: "10"

            # Tiempo total (segundos) que durará el experimento
            - name: TOTAL_CHAOS_DURATION
              value: "60"
``` 

##### **Especificaciones de pruebas**
En esta sección se informan los atributos para las pruebs de validación. El resultado del experiment dependerá del cumplimiento de la validación especificada. 

En el siguiente [enlace](https://docs.litmuschaos.io/docs/litmus-probe/) podréis consultar los tipo de pruebas disponibles.

```yaml
        probe:
          - name: "check-frontend-access-url" # Nombre de prueba
            type: "httpProbe"                 # Petición de tipo HTTP(S). Alternativas: cmdProbe, k8sProbe, promProbe.
            httpProbe/inputs:                  
              url: "http://app-sample.testing.svc.cluster.local" # URL a validar
              insecureSkipVerify: false                               # Permitir HTTP sin TLS
              method:
                get:                          # Petición tipo GET
                  criteria: ==                # Criterio a evaluar
                  responseCode: "200"         # Respuesta a evaluar
            mode: "Continuous"                # La prueba se ejecuta de forma continua (alternativas: SoT, EoT, Edge, OnChaos)
            runProperties:
              probeTimeout: 5                 # Número de segundos para timeout en la petición
              interval: 5                     # Intervalo (segundos) entre re-intentos
              retry: 1                        # Número de re-intento antes de dar por fallida la validación   
              probePollingInterval: 2         # Intervalo (segundos) entre peticiones

```

### **Ejecución de experimentos**

#### **Container Kill**

- **Descripción:** Aborta la ejecución del servicio docker dentro de un pod. La selección del pod es aleatoria.

- **Información oficial del experimento:** [enlace](https://docs.litmuschaos.io/docs/container-kill/)
  
- **Criterio de entrada:** 2 pods de app-sample en estado "Running"
  
  ```bash
    kubectl get pods -n "${TESTING_NAMESPACE}"

    # -----------------------------------------

    NAME                          READY   STATUS    RESTARTS   AGE
    app-sample-7ff489dbd5-82ppw   1/1     Running   0          9h
    app-sample-7ff489dbd5-jg9vh   1/1     Running   0          9h
  ```

- **Parámetros de entrada experimento:**

    ```yaml
    experiments:
        - name: container-kill
        spec:
            components:
            env:
                # provide the chaos interval
                - name: CHAOS_INTERVAL
                value: "10"

                # provide the total chaos duration
                - name: TOTAL_CHAOS_DURATION
                value: "20"

                - name: CONTAINER_RUNTIME
                value: "docker"

                - name: SOCKET_PATH
                value: "/var/run/docker.sock"
    ```

- **Hipótesis:** Tenemos dos pods escuchando por el 8080 tras un balanceador. Nuestro deployment tiene readinessProbe con periodSeconds=1 y failureThreshold=1. Si uno de los pods deja de responder, el balanceador deja de enviar tráfico a ese pod y debe responder el otro. Hemos establecido el healthcheck del experimento cada 5s (tiempo máximo de respuesta aceptable) atacando directamente contra el balanceador, por lo que no deberíamos de tener pérdida de servicio en ningún momento. 

- **Creación de SA, Role y RoleBinding**

    ```bash
    kubectl apply -f src/litmus/kill-container/kill-container-sa.yaml -n "${TESTING_NAMESPACE}"
    ```

- **Ejecución de experimento**

    ```bash
    kubectl apply -f src/litmus/kill-container/chaos-engine-kill-container.yaml  -n "${TESTING_NAMESPACE}"
    
    # Awaited -> Pass/Fail
    watch -n 1 kubectl get chaosresult app-sample-chaos-container-kill -n "${TESTING_NAMESPACE}" -o jsonpath="{.status.experimentstatus.verdict}"
    ```

- **Observaciones:** durante el experimento observamos 2 reinicios de pod con transición "Running" -> "Error" -> "Running". 

- **Validación:** Peticiones get al balanceador con respuesta 200.

    ```yaml
    probe:
    - name: "check-frontend-access-url"
        type: "httpProbe"
        httpProbe/inputs:
        url: "http://app-sample.testing.svc.cluster.local"
        insecureSkipVerify: false
        method:
            get:
            criteria: ==
            responseCode: "200"
        mode: "Continuous"
        runProperties:
        probeTimeout: 5
        interval: 5
        retry: 1
        probePollingInterval: 2
    ```

- **Resultado:** resultado "Pass" (dos pods en estado "Running", sin pérdida de servicio durante la duración del experimento)

    ```bash
    $ kubectl describe chaosresult app-sample-chaos-container-kill -n "${TESTING_NAMESPACE}" 

    # --------------------------------------------------------------------------------------

    Spec:
        Engine:      app-sample-chaos
        Experiment:  container-kill
    Status:
        Experimentstatus:
            Fail Step:                 N/A
            Phase:                     Completed
            Probe Success Percentage:  100
            Verdict:                   Pass
    History:
        Failed Runs:   0
        Passed Runs:   6
        Stopped Runs:  0
    Probe Status:
        Name:  check-frontend-access-url
        Status:
            Continuous:  Passed 👍
        Type:            httpProbe
    Events:
        Type    Reason   Age    From                         Message
        ----    ------   ----   ----                         -------
        Normal  Awaited  4m48s  container-kill-5i56m6-4pkxg  experiment: container-kill, Result: Awaited
        Normal  Pass     4m4s   container-kill-5i56m6-4pkxg  experiment: container-kill, Result: Pass
    
    
    $ kubectl get pods -n testing
    
    NAME                          READY   STATUS    RESTARTS   AGE
    app-sample-6c48f8c4cc-74lvl   1/1     Running   2          25m
    app-sample-6c48f8c4cc-msdmj   1/1     Running   0          25m
    ```

    ![kill-container](./docs/img/kill-container.png)





#### **Pod autoscaler**

- **Descripción:** permite escalar las réplicas para testear el autoescalado en el nodo.

- **Información oficial del experimento:** [enlace](https://docs.litmuschaos.io/docs/pod-autoscaler/)
  
- **Criterio de entrada:** 2 pods de app-sample en estado "Running"
  
  ```bash
    $ kubectl get pods -n "${TESTING_NAMESPACE}"

    # ------------------------------------------

    NAME                          READY   STATUS    RESTARTS   AGE
    app-sample-6c48f8c4cc-74lvl   1/1     Running   2          29m
    app-sample-6c48f8c4cc-msdmj   1/1     Running   0          28m


  ```

- **Parámetros de entrada experimento:**

    ```yaml
    experiments:
      - name: pod-autoscaler
        spec:
          components:
            env:
              # set chaos duration (in sec) as desired
              - name: TOTAL_CHAOS_DURATION
                value: "60"

              # number of replicas to scale
              - name: REPLICA_COUNT
                value: "10"
    ```

- **Hipótesis:** Disponemos de un HPA con min = 2 y max = 10. Con la ejecución de este experimento queremos validar que nuestro nodo es capaz de escalar a 10 réplicas (el máx establecido en el HPA). Cuando ejecutemos el experimento, se crearán 10 réplicas y en ningún momento tendrémos pérdida de servicio. Nuestro HPA tiene establecido el parámetro "--horizontal-pod-autoscaler-downscale-stabilization" a 300s, por lo que durante ese intervalo tendremos 10 réplicas en estado "Running" y transcurrido ese intervalo, volveremos a tener 2 réplicas. 

- **Creación de SA, Role y RoleBinding**

    ```bash
    $ kubectl apply -f src/litmus/pod-autoscaler/pod-autoscaler-sa.yaml -n "${TESTING_NAMESPACE}"
    ```

- **Ejecución de experimento**

    ```bash
    $ kubectl apply -f src/litmus/pod-autoscaler/chaos-engine-pod-autoscaler.yaml  -n "${TESTING_NAMESPACE}"
    ```

- **Observaciones:**

- **Validación:** Peticiones get al balanceador con respuesta 200.

    ```yaml
    probe:
    - name: "check-frontend-access-url"
        type: "httpProbe"
        httpProbe/inputs:
        url: "http://app-sample.testing.svc.cluster.local"
        insecureSkipVerify: false
        method:
            get:
            criteria: ==
            responseCode: "200"
        mode: "Continuous"
        runProperties:
        probeTimeout: 5
        interval: 5
        retry: 1
        probePollingInterval: 2
    ```

- **Resultado:**

    ```bash
    $ kubectl describe chaosresult app-sample-chaos-pod-autoscaler  -n "${TESTING_NAMESPACE}"

    # ----------------------------------------------------------------------------------------

    Spec:
        Engine:      app-sample-chaos
        Experiment:  pod-autoscaler
    Status:
        Experimentstatus:
            Fail Step:                 N/A
            Phase:                     Completed
            Probe Success Percentage:  100
            Verdict:                   Pass
    History:
        Failed Runs:   0
        Passed Runs:   6
        Stopped Runs:  0
    Probe Status:
        Name:  check-frontend-access-url
        Status:
            Continuous:  Passed 👍
        Type:            httpProbe
    Events:
        Type    Reason   Age    From                         Message
        ----    ------   ----   ----                         -------
        Normal  Awaited  4m46s  pod-autoscaler-95wa6x-858jv  experiment: pod-autoscaler, Result: Awaited
        Normal  Pass     3m32s  pod-autoscaler-95wa6x-858jv  experiment: pod-autoscaler, Result: Pass

    $ kubectl get pods -n testing

    # ---------------------------
    
    NAME                          READY   STATUS        RESTARTS   AGE
    app-sample-6c48f8c4cc-5kzpg   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-74lvl   0/1     Running       2          32m
    app-sample-6c48f8c4cc-bflws   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-c5ls8   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-d9zj4   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-f2xnt   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-f7qdl   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-ff84v   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-k29rr   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-l5fqp   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-m587t   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-msdmj   1/1     Running       0          32m
    app-sample-6c48f8c4cc-n5h6l   0/1     Completed     0          39s
    app-sample-6c48f8c4cc-qr5nd   0/1     Completed     0          39s
    app-sample-chaos-runner       0/1     Completed     0          47s
    pod-autoscaler-95wa6x-858jv   0/1     Completed     0          45s
    ```

    ![pod-autoscaler](./docs/img/pod-autoscaler.png)

#### **Pod CPU Hog**

- **Descripción:** permite consumir recursos de CPU dentro de POD

- **Información oficial del experimento:** [enlace](https://docs.litmuschaos.io/docs/pod-cpu-hog/)
  
- **Criterio de entrada:** 2 pods de app-sample en estado "Running"
  
  ```bash
    kubectl get pods -n "${TESTING_NAMESPACE}"

    # ---------------------------------------

    NAME                          READY   STATUS    RESTARTS   AGE
    app-sample-6c48f8c4cc-74lvl   1/1     Running   2          52m
    app-sample-6c48f8c4cc-msdmj   1/1     Running   0          52m

  ```

- **Parámetros de entrada experimento:**

    ```yaml
    experiments:
      - name: pod-cpu-hog
        spec:
          components:
            env:
              #number of cpu cores to be consumed
              #verify the resources the app has been launched with
              - name: CPU_CORES
                value: "1"

              - name: TOTAL_CHAOS_DURATION
                value: "60" # in seconds

              - name: PODS_AFFECTED_PERC
                value: "0"
    ```

- **Hipótesis:**  Disponemos de un HPA con min = 2 y max = 10. Con la ejecucicón de este experimento queremos validar que nuestro HPA funciona correctamente. Tenemos establecido un targetCPUUtilizationPercentage=50%, lo que quiere decir que si inyectamos consumo de CPU en un pod, el HPA debe establecer el número de réplicas a 3 (2 min + 1 autoscaler). En ningún momento debemos tener pérdida de servicio. Nuestro HPA tiene establecido el parámetro "--horizontal-pod-autoscaler-downscale-stabilization" a 300s, por lo que durante ese intervalo tendremos 10 réplicas en estado "Running" y transcurrido ese intervalo, volveremos a tener 2 réplicas.

- **Creación de SA, Role y RoleBinding**

    ```bash
    kubectl apply -f src/litmus/pod-cpu-hog/pod-cpu-hog-sa.yaml -n "${TESTING_NAMESPACE}"
    ```

- **Ejecución de experimento**

    ```bash
    kubectl apply -f src/litmus/pod-cpu-hog/chaos-engine-pod-cpu-hog.yaml -n "${TESTING_NAMESPACE}"
    ```

- **Observaciones:** durante el experimento vemos 2 pod en estado "Runnning". Se comienza a inyectar consumo en uno de los POD y se autoescala a 3 réplicas. A los 300s se vuelve a tener 2 réplicas.

- **Validación:** Peticiones get al balanceador con respuesta 200.

    ```yaml
    probe:
    - name: "check-frontend-access-url"
        type: "httpProbe"
        httpProbe/inputs:
        url: "http://app-sample.testing.svc.cluster.local"
        insecureSkipVerify: false
        method:
            get:
            criteria: ==
            responseCode: "200"
        mode: "Continuous"
        runProperties:
        probeTimeout: 5
        interval: 5
        retry: 1
        probePollingInterval: 2
    ```

- **Resultado:** resultado "Pass" (tres pods en estado "Running", sin pérdida de servicio durante la duración del experimento)

    ```bash
    $ kubectl describe chaosresult app-sample-chaos-pod-cpu-hog -n "${TESTING_NAMESPACE}" 

    # -----------------------------------------------------------------------------------

    Spec:
        Engine:      app-sample-chaos
        Experiment:  pod-cpu-hog
    Status:
        Experimentstatus:
            Fail Step:                 N/A
            Phase:                     Completed
            Probe Success Percentage:  100
            Verdict:                   Pass
    History:
        Failed Runs:   0
        Passed Runs:   6
        Stopped Runs:  0
    Probe Status:
        Name:  check-frontend-access-url
        Status:
            Continuous:  Passed 👍
        Type:            httpProbe
    Events:
        Type    Reason   Age    From                         Message
        ----    ------   ----   ----                         -------
        Normal  Awaited  2m23s  pod-cpu-hog-mpen59-zcpr6  experiment: pod-cpu-hog, Result: Awaited
        Normal  Pass     74s    pod-cpu-hog-mpen59-zcpr6  experiment: pod-cpu-hog, Result: Pass

    $ kubectl get pods -n testing

      NAME                          READY   STATUS      RESTARTS   AGE
      app-sample-6c48f8c4cc-74lvl   1/1     Running     6          46m
      app-sample-6c48f8c4cc-msdmj   1/1     Running     0          46m
      app-sample-5c5575cdb7-hq5gs   1/1     Running     0          49s
      app-sample-chaos-runner       0/1     Completed   0          104s
      pod-cpu-hog-mpen59-zcpr6      0/1     Completed   0          103s
    ```

    ![pod-cpu](./docs/img/pod-cpu.png)


#### **Extra - Otros experimentos**

- **pod-network-loss**

  ```bash
  kubectl apply -f src/litmus/pod-network-loss/pod-network-loss-sa.yaml -n "${TESTING_NAMESPACE}"

  kubectl apply -f src/litmus/pod-network-loss/chaos-engine-pod-network-loss.yaml  -n "${TESTING_NAMESPACE}"

  kubectl describe chaosresult app-sample-chaos-pod-network-loss -n "${TESTING_NAMESPACE}"
  ```
- **pod-memory-hog**
  ```bash
  kubectl apply -f src/litmus/pod-memory/pod-memory-hog-sa.yaml -n "${TESTING_NAMESPACE}"

  kubectl apply -f src/litmus/pod-memory/chaos-engine-pod-memory-hog.yaml  -n "${TESTING_NAMESPACE}"

  kubectl describe chaosresult app-sample-chaos-pod-memory-hog -n "${TESTING_NAMESPACE}" 
  ```

- **pod-delete**
  ```bash
  kubectl apply -f src/litmus/pod-delete/pod-delete-sa.yaml -n "${TESTING_NAMESPACE}"

  kubectl apply -f src/litmus/pod-delete/chaos-engine-pod-delete.yaml -n "${TESTING_NAMESPACE}"

  kubectl describe chaosresult app-sample-chaos-pod-delete -n "${TESTING_NAMESPACE}" 
  ```

### **Planificación de experimentos**

Litmus soporta el uso de planificaciones de experimentos. Dispone de las siguientes opciones:

- **Inmediato**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    now: true
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Timestamp específico**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    once:
      #should be modified according to current UTC Time
      executionTime: "2020-05-12T05:47:00Z" 
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Repeticiones**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      properties:
         #format should be like "10m" or "2h" accordingly for minutes or hours
        minChaosInterval: "2m"  
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Repeticiones entre un rango de fechas**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      timeRange:
        #should be modified according to current UTC Time
        startTime: "2020-05-12T05:47:00Z"   
        endTime: "2020-09-13T02:58:00Z"   
      properties:
        #format should be like "10m" or "2h" accordingly for minutes and hours
        minChaosInterval: "2m"  
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Repeticiones con una fecha de finalización**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      timeRange:
        #should be modified according to current UTC Time
        endTime: "2020-09-13T02:58:00Z"   
      properties:
        #format should be like "10m" or "2h" accordingly for minutes and hours
        minChaosInterval: "2m"   
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Repeticiones desde una fecha de inicio (ejecuciones indefinidas)**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      timeRange:
        #should be modified according to current UTC Time
        startTime: "2020-05-12T05:47:00Z"   
      properties:
         #format should be like "10m" or "2h" accordingly for minutes and hours
        minChaosInterval: "2m" 
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Ejecución entre horas con frecuencia**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      properties:
        #format should be like "10m" or "2h" accordingly for minutes and hours
        minChaosInterval: "2m"   
      workHours:
        # format should be <starting-hour-number>-<ending-hour-number>(inclusive)
        includedHours: 0-12
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

- **Ejecuciones períodicas en días específicos**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosSchedule
metadata:
  name: schedule-nginx
spec:
  schedule:
    repeat:
      properties:
        #format should be like "10m" or "2h" accordingly for minutes and hours
        minChaosInterval: "2m"   
      workDays:
        includedDays: "Mon,Tue,Wed,Sat,Sun"
  engineTemplateSpec:
    appinfo:
      appns: testing
      applabel: app.kubernetes.io/name=app-sample
      appkind: deployment
    annotationCheck: 'true'
```

## **LitmusChaos + *Load Test Performance* con Jmeter**

```bash
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




url=$(minikube service app-sample --url -n "${TESTING_NAMESPACE}")

HOST_APP_SAMPLE=$(echo ${url} | cut -d/ -f3 | cut -d: -f1)
PORT_APP_SAMPLE=$(echo ${url} | cut -d: -f3)
```


```bash
TARGET_RATE=200
RAMP_UP_TIME=60
RAMP_UP_STEPS=1

# GUI mode
bash apache-jmeter/bin/jmeter.sh -t src/jmeter/litmus-k8s-workshop.jmx -f -l apache-jmeter/logs/result.jtl -j apache-jmeter/logs/jmeter.log -Jhost=${HOST_APP_SAMPLE} -Jport=${PORT_APP_SAMPLE} -Jtarget_rate=${TARGET_RATE} -Jramp_up_time=${RAMP_UP_TIME} -Jramp_up_steps=${RAMP_UP_STEPS}
```

```bash
kubectl apply -f src/litmus/pod-network-loss/pod-network-loss-sa.yaml -n "${TESTING_NAMESPACE}"
kubectl apply -f src/litmus/pod-network-loss/chaos-engine-pod-network-loss.yaml  -n "${TESTING_NAMESPACE}"

TARGET_RATE=200
RAMP_UP_TIME=60
RAMP_UP_STEPS=1

bash apache-jmeter/bin/jmeter.sh -n -t src/jmeter/litmus-k8s-workshop.jmx -f -l apache-jmeter/logs/result.jtl -j apache-jmeter/logs/jmeter.log -Jhost=${HOST_APP_SAMPLE} -Jport=${PORT_APP_SAMPLE} -Jtarget_rate=${TARGET_RATE} -Jramp_up_time=${RAMP_UP_TIME} -Jramp_up_steps=${RAMP_UP_STEPS}

rm -rf apache-jmeter/logs/report && bash apache-jmeter/bin/jmeter.sh -g apache-jmeter/logs/result.jtl -o apache-jmeter/logs/report
```

## **Litmus UI Portal**

Litmus dispone de un portal para poder realizar experimentos sin necesidad utilizar la consola. Dispone de las siguientes funcionalidades:

- Gestión de workflows: dispone de todos los experimentos pre-cargados listos para ejecutar en tu k8s.
- MyHubs: permite conectar a repositorios públicos/privados para hacer uso de tus propios experimentos.
- Analytics: permite visualizar las ejecuciones de tus experimentos, así como estadísticas sobre los mismos. Además, permite conectar a otros DataSources como Prometheus.
- Gestión de equipos y usuarios. 


```bash
# install litmus portal
kubectl apply -f src/litmus/portal/portal.yaml

# kubectl apply -f src/litmus/portal.yaml
minikube service litmusportal-frontend-service -n  ${LITMUS_NAMESPACE} > /dev/null &
```

![Litmus Portal](./docs/img/litmus-portal.png)

## **Guía Litmus para desarrolladores** 

En la actualidad, litmus dispone de 48 experimentos a través de [Litmus ChaosHub](https://hub.litmuschaos.io/). Están desarrollados principalmente en Go, aunque disponen de una SDK para python y ansible. 

Los experimentos tienen una estructura bien definida (pre-checks, chaos-injection, litmus-probes, post-checks y result-updates) y es viable desarrollar experimentos que se ajusten a tus necesidades. 

En este [enlace](https://docs.litmuschaos.io/docs/devguide/) encontraréis toda la información para desarrolladores.


## ***Chaos Engineering* en despliegue Continuo**

En este workshop 

## **Consideraciones finales** 

Elaborar un plan de pruebas que te permita conocer el comportamiento íntegro de tu sistema puede ser una tarea relativamente compleja.En este workshop hemos trabajado la inyección de errores en kubernetes utilizando un único servicio bajo un único nodo, pero los sistemas distribuidos suelen ser mucho más complejos: decenas de microservicios ejecutando en múltiples nodos de k8s sobre infraestructura cloud, con alta disponibilidad implementada con multi-AZ/multi-region, comunicaciones con on-premise, etc.

## **Referencias**

- [Litmus official web](https://litmuschaos.io/)
- [Litmus GitHub](https://github.com/litmuschaos/litmu)
- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Chaos Engineering: the history, principles and practice](https://www.gremlin.com/community/tutorials/chaos-engineering-the-history-principles-and-practice/)

## **Licencia**
Este workshop está licenciado bajo licencia MIT (ver [LICENSE](LICENSE) para más detalle).

## **Autor**

Ángel Maroco - [linkedIn](https://www.linkedin.com/in/angelmaroco/) | [github](https://github.com/angelmaroco)







  