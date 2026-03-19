# EKS Secure Enterprise API Builder

This template provides a secure baseline for building and deploying Python APIs from a Coder workspace to Amazon EKS.
It is designed for platform and backend teams that want an opinionated starting point with IRSA, Helm, and Kubernetes
security hardening already wired.

## What this template includes

- Terraform providers for AWS, Kubernetes, and Helm
- IRSA-ready `ServiceAccount` wiring in Terraform and manifests
- Helm chart with Deployment, Service, HPA, PDB, NetworkPolicy, and Ingress
- Raw `k8s/` manifests for direct `kubectl apply` workflows
- Flask API starter service with `/health` and `/v1/echo`
- Secure container runtime defaults (`runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities)

## Required operator variables

See `.env.example` and set values during Coder template import:

- `AWS_REGION`
- `EKS_CLUSTER_NAME`
- `K8S_NAMESPACE`
- `IRSA_ROLE_ARN`
- `IMAGE_REPOSITORY`
- `IMAGE_TAG`
- `API_LOG_LEVEL`
- `INGRESS_HOST`

## Layout

- `coder/` — Coder-facing assets
- `workspace/` — image, bootstrap assets, and API app
- `helm/` — deployable Helm chart
- `k8s/` — raw Kubernetes manifests
- `mcp/` — MCP example configuration

## Deployment notes

1. Build and push your API image to ECR or an approved registry.
2. Create an IRSA role using `docs/iam-policies/secure-enterprise-api-builder-irsa-policy.json`.
3. Import `coder/main.tf` into your Coder control plane.
4. Provide cluster and image parameters in Coder workspace creation.
5. Verify deployment health:
   - `kubectl -n <namespace> get pods`
   - `kubectl -n <namespace> get svc`
   - `kubectl -n <namespace> get hpa`

## Security baseline

- IRSA-only AWS authentication (no long-lived AWS keys in pods)
- Pod Security Standards restricted namespace labels
- Default deny `NetworkPolicy` with explicit allow-listing
- Non-root container execution and read-only filesystem
- PodDisruptionBudget for high-availability maintenance windows

## Next steps for customization

1. Replace `workspace/api.py` with your domain API logic.
2. Add auth middleware (JWT/OIDC) and structured audit logging.
3. Extend Helm values with environment-specific overlays.
4. Add integration tests for API routes and deployment assertions.
