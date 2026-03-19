{{- define "eks-secure-enterprise-api-builder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "eks-secure-enterprise-api-builder.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "eks-secure-enterprise-api-builder.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "eks-secure-enterprise-api-builder.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "eks-secure-enterprise-api-builder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "eks-secure-enterprise-api-builder.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eks-secure-enterprise-api-builder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
