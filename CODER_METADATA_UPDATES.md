# Coder Metadata Integration Updates

## Overview
All Terraform templates have been enhanced with Coder provider integration and metadata resources to display workspace and application information directly in the Coder UI.

## Changes Made

### 1. **Coder Provider Addition**
All templates now include the Coder provider (version >= 0.11.0) in their required providers block:
```hcl
coder = {
  source  = "coder/coder"
  version = ">= 0.11.0"
}
```

### 2. **Coder Provider Configuration**
Each template now initializes the Coder provider:
```hcl
provider "coder" {
}
```

### 3. **Workspace Data Source**
Added a data source to detect when running within Coder:
```hcl
data "coder_workspace" "me" {
}
```

### 4. **Metadata Resources**

#### Workspace Info Metadata
- **Resource**: `coder_metadata.workspace_info`
- **Purpose**: Displays cluster, namespace, model configuration, and service account details
- **Conditional**: Only created when running within Coder workspace
- **Icon**: Amazon Bedrock logo

Metadata fields include:
- cluster
- namespace
- bedrock_model / region (for API Builder)
- ai_provider
- embedding_model (RAG/Enterprise templates)
- knowledge_base (RAG/Enterprise templates)
- cognito_pool (Enterprise template)
- otel_service (Enterprise template)
- service_account

#### Chatbot Access Metadata
- **Resource**: `coder_metadata.chatbot_access` (chatbot templates only)
- **Purpose**: Displays Kubernetes Service configuration for immediate access
- **Conditional**: Only created when running within Coder workspace
- **Icon**: OpenAI logo

Metadata fields include:
- service_name
- service_port
- target_port
- service_type
- status (Ready/Provisioning)

### 5. **Enhanced Outputs**
All templates now have additional outputs for programmatic access:

**Chatbot Templates:**
- `chatbot_service_name` - Kubernetes Service name
- `chatbot_namespace` - Deployment namespace
- `chatbot_loadbalancer_hostname` - AWS LoadBalancer hostname
- `chatbot_loadbalancer_ip` - AWS LoadBalancer IP
- `embedding_model` (RAG/Enterprise)
- `knowledge_base_id` (RAG/Enterprise)
- `cognito_user_pool` (Enterprise)
- `otel_service` (Enterprise)

**API Builder Template:**
- `api_namespace` - Kubernetes namespace
- `api_service_account` - Service Account name

## Templates Updated

1. **eks-bedrock-chatbot-connectors**
   - 2 metadata resources (workspace_info, chatbot_access)
   - 4 new outputs

2. **eks-bedrock-chatbot-rag**
   - 2 metadata resources (workspace_info, chatbot_access)
   - 6 new outputs

3. **eks-bedrock-chatbot-secure-enterprise**
   - 2 metadata resources (workspace_info, chatbot_access)
   - 8 new outputs

4. **eks-bedrock-chatbot-starter**
   - 2 metadata resources (workspace_info, chatbot_access)
   - 3 new outputs

5. **eks-secure-enterprise-api-builder**
   - 1 metadata resource (workspace_info)
   - 2 new outputs

## User Experience Improvements

### In Coder Workspace UI:
1. **Workspace Info Panel**: Users see at a glance:
   - Target EKS cluster
   - Kubernetes namespace
   - AI model configuration
   - Active feature flags (connectors, embeddings, auth)
   - Service Account name

2. **Service Access Panel**: For chatbot templates, users see:
   - Kubernetes Service name and ports
   - Current provisioning status
   - LoadBalancer connection details when ready

### Via Terraform Outputs:
- Automation and scripts can programmatically access service details
- LoadBalancer addresses available for port-forwarding scripts
- Status checks available for health monitoring

## Deployment Notes

- **No breaking changes**: All modifications are additive
- **Safe in non-Coder environments**: Metadata resources gracefully skip creation if not in Coder workspace
- **No additional dependencies**: Uses only existing Coder provider
- **Backward compatible**: All existing outputs remain unchanged

## Future Enhancements

1. Add `coder_agent` resources for IDE/code server integration
2. Implement workspace buttons linking to chatbot URLs
3. Add external auth configuration for enterprise templates
4. Integrate with Coder's resource monitoring dashboards
