# AGENTS.md - SONiC Buildimage Contributor Guidance

## Scope

Repository-wide instructions for AI models, limited to durable build, editing,
and review practices; do not duplicate plans, progress tracking, design
rationale, or migration reports here. Before changing a component, read the
nearest applicable `AGENTS.md`, its build rule, and the associated template or
source file; verify the active build environment, package versions, and
platform support in the checked-out branch rather than assuming from here.
## Branches

Canonical's maintained fork of upstream
[`sonic-net/sonic-buildimage`](https://github.com/sonic-net/sonic-buildimage);
it builds ONIE-compatible switch installer images and service container
images. Upstream maintains date-named release branches (e.g. `202405`,
`202605`) after their branch point; they can be force-rewritten with an
identical tree, so confirm with `git merge-base` before assuming a bad rebase.

- **`feature_noble_build`** is the Ubuntu Noble (24.04) SONiC reference
  branch, migrated from the upstream Debian Bookworm based `202405` branch.
- **`202605_resolute`** is the main Ubuntu Resolute (26.04) SONiC branch,
  migrated from the upstream Debian Trixie based `202605` branch; the
  migration is complete. Only Resolute-based SONiC is built here:
  `BLDENV=resolute` is the default and only enabled build environment, with
  the retained trixie/bookworm paths disabled (`NOTRIXIE=1`, `NOBOOKWORM=1`).

- Migration documentation lives only on the `202605_resolute_doc` branch
  (`docs/superpowers/`) and is authoritative for design, plans, status, and
  compatibility decisions; do not duplicate or edit it without an explicit
  documentation task.

## Build System

The top-level `Makefile` dispatches to `Makefile.work`; `BLDENV` selects the
build environment, and `slave.mk` defines the common build graph, package
paths, and Docker targets. Change packages and images in the relevant
`rules/*.mk` file rather than bypassing that graph. Run the smallest relevant
target first; never run destructive cleanup targets unless required.

## Editing Rules

- Treat Jinja2 templates (`*.j2`) as source files; generated output is not.
  Fix generated code and third-party headers via build flags or explicit
  patch files, never by editing them or downloaded external sources directly.
- Preserve the Docker variant chain: update its rules, base image
  relationship, and template context together.
- Keep pins: do not replace pinned dependencies with rolling `latest`,
  `stable`, or meta-packages, and preserve declared source builds in
  `rules/*.mk` without an approved build-graph update.
- Keep changes minimal and scoped; avoid unrelated formatting and broad
  dependency upgrades.

## Submodules

- Commit submodule changes in the submodule's repository first; then bump the
  gitlink deliberately. Never treat an uncommitted submodule worktree as a
  parent-repository source patch.
- A gitlink commit must be reachable on the remote its `.gitmodules` URL
  names, or clones cannot initialize the submodule. Non-upstream commits go
  to `canonical/<submodule>:202605_resolute` (never `sonic-net/`); push
  local-only commits there first and point the URL at `canonical/<submodule>`.
  The state is not determined by the URL alone — a submodule can carry
  Canonical commits, or commits pushed nowhere at all, while its URL still
  names an upstream remote.
- To pick up upstream changes in a forked submodule, rebase its
  `202605_resolute` branch onto the upstream branch (do not fast-forward over
  the resolute-specific commits), then bump the gitlink. After syncing this
  repository with upstream, run `scripts/submodule-ff-audit.sh`.
- `.gitmodules` URLs must be `https`, not `ssh`; edit an existing
  `[submodule "<short-name>"]` section in place — never append a duplicate
  section or omit `path =`, which git silently ignores.

## Verification and Hygiene

Run the narrowest build, lint, or test target that covers the change; state
clearly if verification cannot be run. For build-environment, base-image,
package, or Docker changes, verify the `BLDENV` and inspect rendered inputs
or build logs. Inspect `git diff` and `git status` before handing off;
preserve unrelated worktree changes.

Use concise commit prefixes (`build:`, `fix:`, `docs:`, `test:`); never
commit local configuration, build output, generated artifacts, editor
settings, or files covered by `.gitignore`.
