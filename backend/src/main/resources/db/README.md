# Backend Schema Migration

## Policy

Flyway migration is the canonical schema change path for the public backend modernization track.

## Current migration

- `migration/V20260714_001__baseline_backend_schema.sql`

This migration defines a baseline schema for:

- users
- projects
- project_files
- boards
- comments
- board_reactions
- terraform_runs

## Rules

- Do not rely on Hibernate auto-DDL for production schema changes.
- Keep `ddl-auto=validate` in production runtime.
- Add new schema changes as a new versioned migration.
- Do not edit an already-applied migration in a shared environment.
- Manual hotfix SQL must be documented separately and treated as emergency recovery material.
