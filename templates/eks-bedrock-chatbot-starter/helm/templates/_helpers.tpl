{{/*
Expand the name of the chart.
*/}}
{{- define "eks-bedrock-chatbot.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "eks-bedrock-chatbot.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "eks-bedrock-chatbot.labels" -}}
helm.sh/chart: {{ include "eks-bedrock-chatbot.name" . }}-{{ .Chart.Version }}
{{ include "eks-bedrock-chatbot.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "eks-bedrock-chatbot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eks-bedrock-chatbot.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
