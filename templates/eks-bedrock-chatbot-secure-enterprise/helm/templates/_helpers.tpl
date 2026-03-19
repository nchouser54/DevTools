{{/*
Expand the name of the chart.
*/}}
{{- define "eks-bedrock-chatbot-enterprise.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "eks-bedrock-chatbot-enterprise.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "eks-bedrock-chatbot-enterprise.labels" -}}
helm.sh/chart: {{ include "eks-bedrock-chatbot-enterprise.name" . }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "eks-bedrock-chatbot-enterprise.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "eks-bedrock-chatbot-enterprise.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eks-bedrock-chatbot-enterprise.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
