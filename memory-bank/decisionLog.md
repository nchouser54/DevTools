# Decision Log

| Date | Decision | Rationale |
| ---- | -------- | --------- |
| 2026-03-17 | Use a template-first repository structure | Shipping a concrete reference template is the fastest path to value and clarifies future automation needs. |
| 2026-03-17 | Make platform/DevOps teams the primary audience | The repo is intended to standardize environments at the platform level rather than serve ad hoc individual setup scripts. |
| 2026-03-17 | Anchor the MVP on a Python AI workspace | A single strong reference implementation is more useful than shallow coverage across many languages. |
| 2026-03-17 | Start MCP support with configuration and documentation | Preconfigured integration is lower risk than custom MCP server development for v1. |
| 2026-03-17 | Store template metadata in JSON | JSON allows lightweight validation with the Python standard library. |
| 2026-03-18 | Introduce lightweight template scaffolding and reusable task templates | Faster experimentation with new Coder template ideas while preserving the repository contract and consistency. |
| 2026-03-18 | Add a secure EKS API builder template tier | Extends the EKS catalog beyond chatbot-specific workloads and provides a reusable secure baseline for platform API services. |
