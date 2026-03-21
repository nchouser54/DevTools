# Coder Task Templates

Use these reusable task templates to implement, harden, and validate new Coder templates consistently.

---

## Task Template A — New Template Scaffold

**When to use**: starting a brand-new template idea.

### Scaffold inputs

- Template name
- Template slug
- Persona/problem statement
- Runtime and base image
- Initial tags

### Scaffold checklist

1. Run scaffold generator (`scripts/scaffold_template.py`)
2. Fill `manifest.json` with accurate owner/version/runtime metadata
3. Update `README.md` with operator variables and usage
4. Implement `coder/main.tf` variables/outputs
5. Update `workspace/bootstrap.sh` with baseline tools
6. Add MCP examples in `mcp/servers.example.json`
7. Validate with `scripts/validate_templates.py`

### Scaffold acceptance criteria

- All required contract files exist
- No secrets committed
- Template docs are operator-usable

---

## Task Template B — Security Hardening Pass

**When to use**: before promoting a template beyond prototype.

### Security checklist

1. Review all configs for plaintext secrets
2. Ensure env vars are placeholders only (`.env.example`)
3. Confirm principle of least privilege in cloud/IAM examples
4. Verify container and bootstrap scripts avoid unsafe defaults
5. Add/update troubleshooting guidance in `README.md`

### Security acceptance criteria

- Security assumptions explicitly documented
- No hard-coded credentials, tokens, or production endpoints

---

## Task Template C — EKS Deployment Readiness

**When to use**: templates deploying to Kubernetes/EKS.

### EKS checklist

1. Verify IRSA pattern (service account annotation + IAM role docs)
2. Validate Helm chart renders with expected values
3. Ensure `/health` endpoint supports readiness/liveness probes
4. Confirm PSS settings (`runAsNonRoot`, RO filesystem, no privilege escalation)
5. Add/verify NetworkPolicy, HPA, and PDB where applicable
6. Document required cluster prerequisites in template `README.md`

### EKS acceptance criteria

- Deployment manifests and Helm chart are aligned
- Operator can deploy with documented parameters only

---

## Task Template D — Integration Test Coverage

**When to use**: Python/Flask or API-centric templates.

### Test coverage checklist

1. Add mocked endpoint tests for health and core API path
2. Mock external cloud SDK calls (`boto3`, etc.)
3. Add error-path tests (400/5xx)
4. Verify contract payload shape in request/response
5. Run tests in local repo venv and capture pass output

### Test coverage acceptance criteria

- Core success and failure paths tested
- Test suite runnable without cloud credentials

---

## Task Template E — Template Idea Review Gate

**When to use**: deciding whether a new idea enters implementation.

### Scorecard

Rate each 1–5:

- Platform impact
- Reuse potential
- Operational risk score
- Time-to-first-value

### Gate decision

- **Ship now**: weighted score ≥ 4.0
- **Incubate**: 3.0–3.9 with reduced v0.1.0 scope
- **Backlog**: < 3.0 until dependencies change

### Review gate acceptance criteria

- Decision and rationale captured in `memory-bank/decisionLog.md`

---

## Task Template F — kubectl Operations & Triage

**When to use**: validating live Kubernetes behavior, debugging workspace deployment issues, or proving day-2 operability for EKS-backed templates.

### kubectl checklist

1. Verify cluster access and current context (`kubectl config current-context`)
2. Confirm namespace exists and is active (`kubectl get ns`)
3. Check workload health (`kubectl get deploy,po,svc -n <namespace>`)
4. Inspect recent warnings/events (`kubectl get events -n <namespace> --sort-by=.lastTimestamp`)
5. Validate pod logs for startup/runtime failures (`kubectl logs -n <namespace> <pod> --tail=200`)
6. Validate service routing/endpoints (`kubectl get svc,endpoints -n <namespace>`)
7. Confirm mounted config/secrets and env wiring (`kubectl describe pod -n <namespace> <pod>`)
8. Record findings and remediation actions in template `README.md` troubleshooting section

### kubectl acceptance criteria

- Operator can reproduce health checks and triage steps using only documented commands
- Deployment issues can be localized to one of: config, secrets, permissions, image, or networking
- Troubleshooting notes are updated with exact symptom → diagnosis → fix guidance
