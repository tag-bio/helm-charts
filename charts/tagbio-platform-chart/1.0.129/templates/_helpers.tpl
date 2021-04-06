{{- define "tagbio.imagePullerContainerSpec" -}}
- command:
    - /bin/sh
    - -c
    - echo "pulled image"
  image: {{ .registry }}/{{ .image }}:{{ .tag }}
  imagePullPolicy: Always
  name: {{ .image }}-{{ .tag }}
{{- end -}}