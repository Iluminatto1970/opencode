# OpenCode Agent Guide

Authoritative instructions for every agent working inside this repo. Keep the commands handy, follow the style rules, and always favor automation over back-and-forth questions.

## Repo & Workflow Basics

- Default branch is `dev`; local `main` may not exist. Base comparisons and rebases on `origin/dev`.
- Install dependencies once per clone with `bun install` (requires Bun ≥ 1.3). `nix develop` is available for hermetic setups, but not required.
- Use parallel tool invocations whenever two shell/file ops are independent; this keeps automation fast and matches maintainer expectations.
- Never run tests or scripts from the repo root unless a command explicitly flips directories; many package.json scripts enforce guarded working dirs.
- If you need a released CLI binary, run `./install --help` (same script served from https://opencode.ai/install) or `./install --binary <path>` for custom bits.

## Build, Dev, and Release Commands

- `bun dev` runs the CLI/TUI in watch mode. `bun dev <dir>` targets a specific workspace, `bun dev .` runs against the repo itself, and `bun dev web` opens the browser client.
- Backend/headless API: `bun dev serve --port 4096` (default port 4096). Add `--inspect=ws://localhost:6499` when you need breakpoints; prefer `bun dev spawn` if the worker-thread server hides breakpoints.
- Web UI hot reload: `bun run --cwd packages/app dev` after the server is running. Never rely on `opencode dev web` for UI tweaks because it proxies production CSS/JS.
- Desktop shell (Tauri v2): `bun run --cwd packages/desktop tauri dev` for live reload or `bun run --cwd packages/desktop tauri build` for distributables. Never call `invoke` manually inside the desktop package—only use `packages/desktop/src/bindings.ts`.
- CLI single-file build: `./packages/opencode/script/build.ts --single` (outputs `packages/opencode/dist/opencode-<platform>/bin/opencode`). Rebuild the JS SDK with `./packages/sdk/js/script/build.ts` whenever server contracts change.
- Agent browser automation: install `agent-browser` (via the CLI toolchain) and run `agent-browser open <url>`, then `agent-browser snapshot -i` to enumerate interactable nodes, followed by `agent-browser click @e1` / `fill @e2 "text"` and re-snapshot after changes.

## Test & Lint Matrix

- Turbo orchestration: `bun turbo typecheck` (depends on `build`), `bun turbo run opencode#test` and `bun turbo run @opencode-ai/app#test` respect package build deps.
- Core package (`packages/opencode`):
  - Unit tests: `bun --cwd packages/opencode test` (defaults to `bun test --timeout 30000`). Run a single file with `bun --cwd packages/opencode test src/foo.test.ts` or by title using `-t "matches name"`.
  - Typecheck: `bun --cwd packages/opencode typecheck`.
  - DB migrations: `bun --cwd packages/opencode run db generate --name <slug>` writes `migration/<timestamp>_<slug>/migration.sql` and `snapshot.json`; schema lives in `src/**/*.sql.ts` and uses snake_case.
  - Test fixtures: use `await using tmp = await tmpdir({ git: true, config: {...} })` from `packages/opencode/test/fixture/fixture.ts`. `tmp.path` auto-cleans, `tmp.extra` holds custom init return values.
- Web app (`packages/app`):
  - Unit tests: `bun --cwd packages/app run test:unit` (`bun test --preload ./happydom.ts ./src`). Watch mode with `test:unit:watch`.
  - Playwright e2e: `bun --cwd packages/app test:e2e` (all), `bun --cwd packages/app test:e2e -- e2e/app/home.spec.ts` (single file), `bun --cwd packages/app test:e2e -- -g "button toggles"` (by title), `bun --cwd packages/app test:e2e:ui` (headed UI), and `bun --cwd packages/app test:e2e:local` (brings up backend+frontend).
  - Always import `test`/`expect` from `../fixtures`, rely on helpers in `e2e/actions.ts` & `selectors.ts`, and prefer semantic/data selectors over classes. Use `modKey` for keyboard shortcuts.
- Desktop package: no bespoke test runner, but Tauri requires the Rust toolchain plus GTK/WebKit packages (see https://v2.tauri.app/start/prerequisites and ensure `libwebkit2gtk-4.1-dev`, `libxdo-dev`, `libayatana-appindicator3-dev`, etc. are installed on Linux).
- Root lint hooks: there is no repo-wide eslint; `packages/opencode` reuses its test suite for `lint`. Run `bun --cwd packages/opencode lint` only if Bun-based coverage is acceptable.
- Never restart the OpenCode server or app from automation when debugging the UI—attach to the running process instead, as enforced in `packages/app/AGENTS.md`.

## Running Single Tests Cheat Sheet

```bash
# packages/opencode
bun --cwd packages/opencode test src/session/session.test.ts
bun --cwd packages/opencode test -t "creates workspace"

# packages/app unit tests
bun --cwd packages/app test:unit -- src/components/foo.test.ts

# Playwright e2e
bun --cwd packages/app test:e2e -- e2e/app/home.spec.ts
bun --cwd packages/app test:e2e -- -g "sidebar can be toggled"
```

## Styling & Code Conventions

- Prefer single-word identifiers; only add another word when ambiguity would break clarity. Inline values that are used once to keep variable counts low.
- Imports: keep side-effect imports rare, order internal modules after std/lib. For Playwright tests, always import from `../fixtures`; for desktop bindings import from `./src/bindings`.
- Types: avoid `any`. Let inference work wherever possible. Exported functions can declare return types; internal helpers should lean on inference.
- Errors: favor early returns instead of nested `if/else`. Use `Result`-style helpers where available; keep `try/catch` minimal and scoped to boundaries.
- Control flow: no `else` after a `return`. Replace `if/else` assignments with ternaries or guard clauses.
- Variables: default to `const`; prefer ternaries/guards over reassigning. Use Bun utilities (`Bun.file`, `Bun.write`) rather than Node fs wrappers when feasible.
- Destructuring: only when it shortens repeated access; otherwise use dot notation (`obj.value`) to retain context.
- Collections: favor functional methods (`map`, `filter`, `flatMap`). When filtering to a narrowed type, use a type guard so downstream code stays strongly typed.
- Formatting: Prettier config lives in `package.json` (`semi: false`, `printWidth: 120`). Use `bunx prettier --write` or `bun run --prettier --write src/**/*.ts` from package scripts.
- Imports from other workspaces should reference the package entrypoint (`@opencode-ai/sdk`, `@opencode-ai/util`) rather than deep relative paths.
- SolidJS: prefer `createStore` over juggling multiple `createSignal`s. Keep derived signals as derived stores, and colocate actions near the consuming component.
- Desktop/Tauri: never call `window.__TAURI__.invoke` (use generated bindings) and respect security defaults (keep CSP null only when necessary).
- Tests: avoid mocks when an integration path exists. Use the shared tmpdir fixture for filesystem work; clean up resources using `await using` or helper utilities.
- CSS/Selectors: rely on `data-component` / roles for Playwright tests. Never assert on generated class names.

## Additional Package-Specific Notes

- `packages/app`: backend lives at `http://localhost:4096` during dev. When running via `bun dev --conditions=browser`, make sure the backend is already up; do **not** restart the process mid-test.
- `packages/app/e2e`: spec layout is `e2e/<feature>/*.spec.ts`. Helpers: `withSession` for lifecycle-managed workspace creation, `gotoSession(id?)` to load sessions, `modKey` for shortcuts.
- `packages/opencode/test`: `tmpdir({ git: true })` optionally initializes a repo with a root commit; `config` writes `opencode.json`. `init/ dispose` let you seed and tear down bespoke fixtures.
- `packages/desktop`: keep command/event typings in sync with generated bindings by running the codegen scripts whenever Rust-side APIs change.

## Tooling Guardrails

- Use `bunx` or package scripts for third-party CLIs (eslint, playwright) instead of global installs.
- No Cursor or Copilot instruction files exist in this repo today; this guide, the package-specific AGENTS notes, and `CONTRIBUTING.md` are the sources of truth.
- Remember to regenerate artifacts after touching protocols: `./packages/sdk/js/script/build.ts` (SDK), `bun run --cwd packages/opencode db generate --name <slug>` (migrations), and `bun run --cwd packages/app test:e2e:report` before sharing Playwright output.

Stay automated, stay parallel, and keep this file close—every agent is expected to follow it.
