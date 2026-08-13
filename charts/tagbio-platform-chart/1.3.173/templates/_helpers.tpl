{{- define "tagbio.coreStackService" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    deployment.tag.bio/name: {{ .name }}
    firewall.tag.bio/role: {{ .firewall }}
  name: {{ .name }}
  namespace: {{ .Values.tagbio.namespaces.app }}
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      deployment.tag.bio/name: {{ .name }}
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
    type: RollingUpdate
  template:
    metadata:
      labels:
        deployment.tag.bio/name: {{ .name }}
        deployment.tag.bio/helm-chart-version: {{ .Chart.Version }}
        firewall.tag.bio/role: {{ .firewall }}
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - preference:
              matchExpressions:
              - key: tagbio-controller
                operator: NotIn
                values:
                - "true"
            weight: 100
          - preference:
              matchExpressions:
              - key: tagbio-controller
                operator: DoesNotExist
            weight: 99
      containers:
        - envFrom:
            - secretRef:
                name: {{ .name }}
          image: platform-registry.dev.tag.bio/{{ .name }}:{{ .Values.tagbio.imageTag }}
          imagePullPolicy: Always
          name: {{ .name }}
          resources:
            requests:
              cpu: 100m
              memory: 500Mi
          stdin: true
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          tty: true
{{- if .storageVolume }}
          volumeMounts:
            - mountPath: /storage
              name: storage
{{- end }}
      imagePullSecrets:
        - name: tagbio-platform-registry-creds
        - name: tagbio-cluster-registry-creds
      restartPolicy: Always
{{- if .storageVolume }}
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: tagbio-storage
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  namespace: {{ .Values.tagbio.namespaces.app }}
spec:
  clusterIP: None
  ports:
  - name: http
    port: 8000
    protocol: TCP
    targetPort: 8000
  selector:
    deployment.tag.bio/name: {{ .name }}
  sessionAffinity: None
  type: ClusterIP

{{- end -}}

{{- define "tagbio.controllerAffinity" -}}
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - preference:
        matchExpressions:
        - key: tagbio-controller
          operator: In
          values:
          - "true"
      weight: 100
{{- end -}}

{{- define "tagbio.controllerAntiAffinity" -}}
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - preference:
        matchExpressions:
        - key: tagbio-controller
          operator: NotIn
          values:
          - "true"
      weight: 100
    - preference:
        matchExpressions:
        - key: tagbio-controller
          operator: DoesNotExist
      weight: 99
{{- end -}}

{{- define "tagbio.imagePullerContainerSpec" -}}
- command:
    - /bin/sh
    - -c
    - echo "pulled image {{ .image }}:{{ .tag }}.  Waiting to recycle" && sleep {{ .interval | default 3600 }}
  image: {{ .registry }}/{{ .image }}:{{ .tag }}
  {{- /* Always = check the registry digest each recycle and download ONLY
         when the image actually changed; unchanged digests are a no-op. */}}
  imagePullPolicy: Always
  {{- /* container names are DNS-1123 labels: no dots (tags like
         release-2026.08.13 must be sanitized) */}}
  name: {{ printf "%s-%s" .image .tag | replace "." "-" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "tagbio.secretPreamble" -}}
apiVersion: v1
kind: Secret
metadata:
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-5"
    helm.sh/resource-policy: keep
  name: {{ .name }}
  namespace: {{ .namespace }}
type: Opaque
stringData:
{{- end -}}
