{{- define "tagbio.imagePullerContainerSpec" -}}
- command:
    - /bin/sh
    - -c
    - echo "pulled image"
  image: {{ .registry }}/{{ .image }}:{{ .tag }}
  imagePullPolicy: Always
  name: {{ .image }}-{{ .tag }}
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
