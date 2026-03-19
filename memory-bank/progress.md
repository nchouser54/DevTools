# Progress

## Done

- [x] Initialize project
- [x] Clarify the repository MVP and target users
- [x] Establish the initial repo structure for docs, scripts, and templates
- [x] Replace placeholder documentation with implementation-ready project context
- [x] Scaffold the Python AI workspace reference template
- [x] Add template validation tooling
- [x] Validate the reference template structure

- [x] Scaffold EKS Bedrock Chatbot Starter template (Bedrock Converse, IRSA, k8s manifests, Helm)
- [x] Scaffold EKS Bedrock Chatbot Connectors template (GitHub, Jira, Confluence MCP, feature flags)
- [x] Scaffold EKS Bedrock Chatbot RAG template (Bedrock Knowledge Bases, S3 ingestion CronJob, HPA)
- [x] Scaffold EKS Bedrock Chatbot Secure Enterprise template (Cognito SSO, ESO, PDB, OTel, PSS)
- [x] Update template contract with EKS optional file conventions
- [x] Wire real Terraform providers (aws, kubernetes, helm) in all EKS template `coder/main.tf` files
- [x] Add IAM policy JSON examples for all EKS chatbot tiers
- [x] Add Coder import workflow documentation for all tiers
- [x] Convert chatbot services to Flask with `/health` endpoints and Helm probes
- [x] Add mocked integration tests for starter, rag, enterprise, and ingestion workflows
- [x] Add lightweight template scaffold generator (`scripts/scaffold_template.py`)
- [x] Add template ideation and execution accelerators (`docs/template-idea-backlog.md`, `docs/coder-task-templates.md`)
- [x] Strengthen template validator rules (slug-dir alignment, non-empty manifest fields/tags, skip hidden artifact dirs)
- [x] Build and scaffold EKS Secure Enterprise API Builder template (Terraform + Helm + raw k8s manifests + IRSA policy example)

## Doing

- [ ] Validate EKS templates against live Coder + EKS environment

## Next

- [ ] Add end-to-end integration test for chatbot.py against a sandbox Bedrock account
- [ ] Build and validate the next non-EKS template candidate (Node/TypeScript AI workspace)
