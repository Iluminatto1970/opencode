# OpenCode Agent Guide

Operational defaults for agentic coding in this repository.
Use this unless a deeper package-local AGENTS.md overrides a detail.

## Repository Basics

- Base branch is usually `origin/dev` (not always `main`).
- Runtime/package manager is Bun (Bun >= 1.3 expected).
- Monorepo task runner is Turbo.
- Prefer package-scoped commands via `--cwd`.
- Avoid destructive git commands unless explicitly requested.

## Setup

```bash
bun install
```

- Optional reproducible environment: `nix develop`.
- Install helper script exists at `./install`.
- Prefer `bunx`/package scripts over globally installed CLIs.

## Build, Dev, Lint, Typecheck, Test Commands

Use these as canonical command patterns:

```bash
# Core dev
bun dev
bun dev .
bun dev serve --port 4096

# Web dev
bun run --cwd packages/app dev

# Desktop (Tauri)
bun run --cwd packages/desktop tauri dev
bun run --cwd packages/desktop tauri build

# Turbo level validation
bun turbo typecheck
bun turbo run opencode#test
bun turbo run @opencode-ai/app#test

# packages/opencode
bun --cwd packages/opencode typecheck
bun --cwd packages/opencode lint
bun --cwd packages/opencode test
bun --cwd packages/opencode run db generate --name <slug>

# packages/app
bun --cwd packages/app run test:unit
bun --cwd packages/app test:e2e
bun --cwd packages/app test:e2e:ui
bun --cwd packages/app test:e2e:local
```

Notes:

- DB migration output: `migration/<timestamp>_<slug>/migration.sql` and `snapshot.json`.
- Drizzle schema files live in `src/**/*.sql.ts`.
- For desktop UI code, use `packages/desktop/src/bindings.ts`; do not call raw Tauri invoke directly.

## Running A Single Test (Important)

```bash
# opencode: single file
bun --cwd packages/opencode test src/session/session.test.ts

# opencode: by title
bun --cwd packages/opencode test -t "creates workspace"

# app unit: single file
bun --cwd packages/app test:unit -- src/components/foo.test.ts

# playwright: single file
bun --cwd packages/app test:e2e -- e2e/app/home.spec.ts

# playwright: by title
bun --cwd packages/app test:e2e -- -g "sidebar can be toggled"
```

## Code Style Guidelines

### Formatting

- Prettier is authoritative (`semi: false`, `printWidth: 120`, configured in root `package.json`).
- Keep diffs focused; avoid unrelated reformatting.

### Imports

- Order imports by scope: stdlib/external first, workspace/internal after.
- Prefer workspace entrypoints (e.g. `@opencode-ai/sdk`) over deep cross-package relative imports.
- Avoid side-effect imports unless necessary.

### Types

- Avoid `any`; use explicit narrowing and type guards.
- Prefer inference for local helpers.
- Add explicit types for exported/public APIs when clarity benefits.

### Naming

- Use short, precise names that match nearby code patterns.
- Expand names only when disambiguation is needed.
- SQL naming follows snake_case conventions.

### Control Flow

- Prefer guard clauses and early returns over nested branching.
- Avoid `else` after `return`.
- Default to `const`; keep mutable reassignment minimal.

### Error Handling

- Catch errors at boundaries, not deep inside pure logic.
- Keep `try/catch` blocks narrow and purposeful.
- Preserve error context when wrapping or rethrowing.

### Collections And Data Access

- Prefer `map`/`filter`/`flatMap` when they improve readability.
- Use direct property access when destructuring reduces clarity.

## Testing Conventions

- Prefer integration paths when feasible; avoid over-mocking.
- For `packages/opencode` filesystem tests, use shared tmp fixtures (`tmpdir(...)`).
- In Playwright tests, import `test`/`expect` from `../fixtures`.
- Prefer semantic/data selectors; do not assert on generated class names.

## Package-Specific Notes

- `packages/app` backend default is `http://localhost:4096`.
- During UI debugging, attach to running backend rather than restarting mid-flow.
- Regenerate desktop bindings when Rust-side command/event signatures change.
- Rebuild JS SDK (`./packages/sdk/js/script/build.ts`) after contract/API changes.

## Agent Workflow Expectations

- Run independent tool calls in parallel when possible.
- Read nearby code before introducing new abstractions.
- Never revert unrelated user changes.
- Commit/push only when explicitly requested.

## Cursor/Copilot Rules Status

Checked these locations:

- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`
  Result: none found at the time of writing.
  If these files are added later, treat them as mandatory supplemental instructions.

## Quick Command Block

```bash
bun install
bun dev
bun dev serve --port 4096
bun run --cwd packages/app dev
bun turbo typecheck
bun --cwd packages/opencode test src/session/session.test.ts
bun --cwd packages/app test:e2e -- e2e/app/home.spec.ts
```

Keep changes minimal, verify with targeted tests first, then broaden validation.
