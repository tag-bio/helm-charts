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
  replicas: {{ index .Values.tagbio.coreStack.replicas .name | default 1 }}
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
{{- with .Values.tagbio.podAnnotations }}
      annotations:
{{ toYaml . | indent 8 }}
{{- end }}
      labels:
        deployment.tag.bio/name: {{ .name }}
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
{{- $csSN := ((.Values.tagbio.coreStack | default dict).stableNode | default dict) }}
{{- if $csSN.enabled }}
          - preference:
              matchExpressions:
              - key: {{ $csSN.labelKey | default "tagbio-stable" }}
                operator: In
                values:
                - {{ $csSN.labelValue | default "true" | quote }}
            weight: 100
{{- end }}
{{- if and $csSN.enabled $csSN.required }}
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: {{ $csSN.labelKey | default "tagbio-stable" }}
                operator: In
                values:
                - {{ $csSN.labelValue | default "true" | quote }}
{{- end }}
{{- if and $csSN.enabled (ternary $csSN.tolerate true (hasKey $csSN "tolerate")) }}
      tolerations:
        - key: {{ $csSN.taintKey | default ($csSN.labelKey | default "tagbio-stable") }}
          operator: Equal
          value: {{ $csSN.taintValue | default ($csSN.labelValue | default "true") | quote }}
          effect: NoSchedule
{{- end }}
      containers:
        - envFrom:
            - secretRef:
                name: {{ .name }}
          image: platform-registry.dev.tag.bio/{{ .name }}:{{ .Values.tagbio.imageTag }}
          imagePullPolicy: Always
          name: {{ .name }}
{{- with .env }}
          env:
{{ . | indent 12 }}
{{- end }}
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
    {{- if .Values.tagbio.enforceWorkerScheduling }}
    {{- /* HARD exclusion (1.3.174): a user/FC workload once OOMed the
           controller node; preferred-only affinity is ignored under
           pressure. Gated by tagbio.enforceWorkerScheduling so
           environments opt in via answers (backward compatible). */}}
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: tagbio-controller
          operator: NotIn
          values:
          - "true"
    {{- end }}
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

{{/*
tagbio.mcpResource: the OAuth resource / token audience for the MCP server, exactly as the
connector types the URL. login-service mints tokens with this aud, kung must list it in
KUNG_IDP_CLIENT_IDS, and tagbio-mcp advertises it as TAGBIO_MCP_PUBLIC_URL -- one definition so
the three can never drift (kung compares aud as an exact string).
*/}}
{{- define "tagbio.mcpResource" -}}
https://{{ .Values.tagbio.hosts.cluster }}{{ ((.Values.tagbio.mcp | default dict).path | default "/mcp") }}
{{- end -}}

{{/*
tagbio.oauthEnabled: "true" when tagbio.mcp.enabled AND tagbio.mcp.oauth.enabled are both on,
string-safe (Rancher legacy-catalog answers arrive as the strings "true"/"false", and Helm
treats the string "false" as truthy). Empty otherwise, so `if (include ...)` gates cleanly.
*/}}
{{- define "tagbio.oauthEnabled" -}}
{{- $mcp := .Values.tagbio.mcp | default dict -}}
{{- if and (eq (toString $mcp.enabled) "true") (eq (toString ((($mcp.oauth | default dict).enabled))) "true") -}}
true
{{- end -}}
{{- end -}}

{{/* tagbio.mcpDiscoveryPaths: the /.well-known paths tagbio-mcp serves for OAuth discovery. */}}
{{- define "tagbio.mcpDiscoveryPaths" -}}
- /.well-known/oauth-protected-resource
- /.well-known/oauth-authorization-server
- /.well-known/openid-configuration
{{- end -}}
