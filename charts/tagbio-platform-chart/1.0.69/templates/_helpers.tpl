{{- define "tagbio.imagePullerContainerSpec" -}}
- args:
    - sh
    - -c
    - echo "pulled image"
  image: {{ .registry }}/{{ .image }}:{{ .tag }}
  imagePullPolicy: Always
  name: periodic-image-puller
{{- end }}