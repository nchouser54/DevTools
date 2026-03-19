# Project Brief

## Purpose

Build a template-first toolkit for platform and DevOps teams that want to standardize developer workspaces in Coder with built-in MCP support.

## Problem Statement

Engineering platform teams need a reusable way to ship secure, repeatable, AI-capable development environments without rebuilding workspace images, bootstrap logic, and MCP configuration from scratch for every team.

## Target Users

- Platform engineering teams operating Coder
- DevOps teams maintaining internal engineering environments
- Internal developer productivity teams standardizing AI-ready workspaces

## MVP

The MVP is a single, high-quality Python AI workspace template that demonstrates:

- how templates are structured in this repository
- how MCP server configuration is packaged and documented
- how environment variables and secrets are surfaced safely
- how template quality is validated before expansion to other languages

## Constraints

- No secrets may be committed to the repository
- MCP support should begin with configuration and integration, not custom server development
- The first implementation should remain lightweight and inspectable by operators
- Automation should follow proven repetition rather than precede it

## Success Criteria

- The repository documents a clear template contract
- The Python reference template is understandable and reusable
- Validation tooling catches missing required files and metadata
- Contributors can extend the pattern to additional templates without rethinking the structure
