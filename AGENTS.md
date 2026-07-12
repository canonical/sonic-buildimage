# AGENTS.md - SONiC Buildimage Contributor Guidance

## Scope and Purpose

This file contains repository-wide instructions for human contributors and
automation. Keep it limited to durable build, editing, and review practices.
Project plans, progress tracking, design rationale, and migration reports must
not be duplicated here.

Before changing a component, read the nearest applicable `AGENTS.md`, its build
rule, and the associated template or source file. Do not infer the active build
environment, package version, or platform support from this file; verify it in
the checked-out branch and relevant build configuration.

## Overview

This repository is Canonical's maintained fork of the upstream
[`sonic-net/sonic-buildimage`](https://github.com/sonic-net/sonic-buildimage)
build infrastructure for SONiC, an open-source network operating system. It
builds ONIE-compatible switch installer images and service container images.
See [`README.md`](README.md) for general SONiC usage, supported platforms, and
build prerequisites.

## Branch and Origin

- **Canonical repository:** `canonical/sonic-buildimage`
- **Upstream source:** `sonic-net/sonic-buildimage`
- **Upstream release model:** Date-named release branches such as `202405` are
  maintained after their branch point; they are not immutable release tags.
- **Current branch:** Verify its base, active build environment, and divergence
  from upstream using its Git history and build configuration before making a
  change.

The `feature_noble_build` branch is the reliable Ubuntu Noble (24.04) SONiC
reference implementation. It was migrated from the upstream Debian Bookworm
based `202405` branch.

## Build System

- The top-level `Makefile` dispatches to `Makefile.work`; build-environment
  selection is controlled by `BLDENV`.
- `slave.mk` defines the common build graph, package paths, and Docker targets.
  Make package or image changes in the relevant `rules/*.mk` file rather than
  bypassing that graph with ad hoc build commands.
- `rules/config.user` is a local, ignored configuration file. Do not add it to
  commits or rely on its local values as repository defaults.
- Use the repository's declared targets for builds. For example:

  ```bash
  make sonic-slave-build BLDENV=<environment>
  make PLATFORM=<platform> BLDENV=<environment> target/sonic-<platform>.bin
  make docker-<image> BLDENV=<environment>
  ```

Run the smallest relevant target first. Do not run destructive cleanup targets
unless the task requires them.

## Editing Rules

- Treat Jinja2 templates (`*.j2`) as source files. Generated Dockerfiles,
  scripts, manifests, and build artifacts are not the source of truth.
- Preserve the existing Docker variant chain. When adding or changing a variant,
  update its corresponding rules, base image relationship, and template context
  together.
- Pin package versions where a rule already pins them. Do not replace a pinned
  dependency with a rolling `latest`, `stable`, or meta-package without an
  explicit compatibility decision.
- Preserve source builds declared in `rules/*.mk` unless the change is explicitly
  approved and includes the corresponding build-graph update.
- Do not directly modify source code downloaded from external projects during a
  build. If a change is necessary, add a maintained patch file and apply it
  explicitly from the relevant build rule or script.
- Prefer build flags or local compatibility patches for generated code and
  third-party headers. Do not directly edit generated output.
- Make a minimal, scoped change. Avoid unrelated formatting, generated-file
  updates, or broad dependency upgrades.

## Submodules

- Changes to submodule source must be committed in that submodule's repository
  and branch first; then update this repository's gitlink deliberately.
- Do not treat an uncommitted submodule worktree as a parent-repository source
  patch.
- Before changing a gitlink, verify its remote, branch, and intended commit.

## Resolute Migration Work

For work specifically targeting the Debian Trixie to Ubuntu Resolute migration:

- Use Ubuntu Resolute (26.04) only. Do not substitute an earlier Ubuntu release.
- Preserve the procured kernel ABI unless the task explicitly approves changing
  it.
- Keep Docker and containerd packages pinned to the versions selected by the
  relevant rule; do not use rolling package channels.
- Treat explicitly documented skipped components and accepted workarounds as
  intentional. Do not "fix" them without a task that changes the documented
  decision.
- Follow the established Resolute Docker variant naming and template flow rather
  than altering the Trixie path as a shortcut.
- When an uncertain migration issue arises, inspect the equivalent Debian
  Bookworm-to-Noble migration in `feature_noble_build`. Determine whether its
  solution applies to Resolute, then provide developers with a concise summary
  of the approach, feasibility, and trade-offs before implementing it.
- Do not let a non-critical feature block the overall migration indefinitely.
  When its migration cost is disproportionate, assess the impact of disabling
  it and present that assessment to developers for a decision. The Noble
  migration's disabled FIPS and DASH engine functionality are examples of this
  type of explicit scope decision.

The migration documentation directory, `docs/`, exists only on the
`202605_resolute_doc` branch. It is intentionally absent from the migration
work branch, `202605_resolute`. The following documents on
`202605_resolute_doc` are authoritative for migration design, implementation
plans, current status, compatibility decisions, verification, and
Resolute-specific behavior. Do not duplicate or edit these documents unless the
task explicitly requests documentation work. The English documents are the
source of truth.

- [Migration design](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/specs/2026-07-03-sonic-202605-resolute-migration-design-en.md)
- [Migration implementation plan](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/plans/2026-07-03-sonic-202605-resolute-migration-plan-en.md)
- [VS migration report](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/resolute-vs-migration-report-en.md)
- [Modification catalog](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/resolute-modification-catalog-en.md)
- [Migration code review](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/resolute-migration-code-review-en.md)
- [Superrepo push design](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/specs/2026-07-06-sonic-202605-resolute-superrepo-push-design-en.md)
- [Superrepo push plan](https://github.com/canonical/sonic-buildimage/blob/202605_resolute_doc/docs/superpowers/plans/2026-07-06-sonic-202605-resolute-superrepo-push-plan-en.md)

## Change Verification

- Run the narrowest build, lint, or test target that covers the change. State
  clearly if verification cannot be run and why.
- For build-environment, base-image, package, or Docker changes, verify the
  selected `BLDENV` and inspect the rendered inputs or build logs as appropriate.
- Inspect `git diff` and `git status` before handing off changes. Preserve
  unrelated worktree changes.

## Git Hygiene

- Use a concise commit prefix appropriate to the change, such as `build:`,
  `fix:`, `docs:`, or `test:`.
- Follow the repository's signing policy when creating commits.
- Do not commit local configuration, build output, generated artifacts, editor
  settings, or presentation files covered by `.gitignore`.
