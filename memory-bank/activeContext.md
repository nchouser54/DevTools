# Active Context

## Current Goals

- Deliver a full EKS-native Coder template catalog for AWS Bedrock chatbot workloads
- Maintain a clear progression path: starter → connectors → rag → secure-enterprise

## Current Workstream

- Four EKS Bedrock chatbot templates fully scaffolded and validated against the template contract
- New EKS Secure Enterprise API Builder template added for non-chatbot secure service workloads
- All templates follow IRSA, PSS, NetworkPolicy, and no-plaintext-secrets security baseline
- Lightweight template generation and ideation accelerators added (`scripts/scaffold_template.py`, idea backlog, coder task templates)

## Current Blockers

- No live EKS cluster or Bedrock account available for end-to-end testing
- MCP server npm packages (@modelcontextprotocol/server-jira, server-confluence) are community packages; verify package names before production use
