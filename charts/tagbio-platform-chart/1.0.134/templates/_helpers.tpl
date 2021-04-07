{{- define "tagbio.coreStackService" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    deployment.tag.bio/name: {{ .name }}
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
    spec:
      containers:
        - envFrom:
            - secretRef:
                name: {{ .name }}
          image: platform-registry.dev.tag.bio/{{ .name }}:{{ .Values.tagbio.imageTag }}
          imagePullPolicy: IfNotPresent
          name: {{ .name }}
          resources:
            requests:
              cpu: 100m
              memory: 500Mi
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
    - echo "pulled image"
  image: {{ .registry }}/{{ .image }}:{{ .tag }}
  imagePullPolicy: Always
  name: {{ .image }}-{{ .tag }}
{{- end -}}

{{- define "tagbio.secretPreamble" -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
type: Opaque
stringData:
{{- end -}}
