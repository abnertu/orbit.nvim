# AGENTS Instructions

## Git

- Write commits in [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) format.
- Start the type, scope and description in lowercase. Preserve the case of code identifiers.
- Explain non-trivial changes in a commit body.
- Mark breaking changes with `!` and a `BREAKING CHANGE:` footer.
- Author commits as the user alone. Do not add agent trailers or session links.
- Commit as the approved plan progresses.
- Keep each scoped change reviewable in its own branch and pull request.
- Push approved development work without requesting repeated user approval.
- Run the required Linux and Windows CI checks before merging each pull request.
- Use GitHub's `rebase` merge method when the reviewed change passes all required checks.
- Delete merged topic branches after verifying the target contains their changes.
- Report a blocked branch deletion; never report deletion without confirmation.
- Do not force-push or merge failed, incomplete, or unreviewed changes.
- Keep `.plans/`, logs, throwaway tests and personal settings outside tracked files.
- Do not modify the legacy configuration's default branch as part of a migration experiment.

## Releases

- Follow [Semantic Versioning 2.0.0](https://semver.org/).
- Use bare release tags, such as `1.2.3`, unless an established prefix requires another format.
- Use [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) for a changelog.
- Prepare the version and changelog together before the release.
- Push the release commit before its annotated tag.
- Wait for the default-branch validation to pass before tagging.
- Push the tag alone, after approval.
- Do not use `git push --follow-tags`.

## Code

- Keep one public namespace under `orbit`.
- Write runtime code, tooling, generators and tests in Lua by default.
- Prefer Neovim built-in Lua APIs over Python packages or external runtime dependencies.
- Use another language only for a concrete limitation. Document the reason at its source.
- Keep JSON Schema and GitHub Actions YAML as declarative formats, not executable scripts.
- Give every module a `setup(opts)` entry point and matching `capture(opts)` / `restore(snapshot)` lifecycle hooks.
- Use explicit option types and validate settings before module activation.
- Keep declarations separate from runtime side effects.
- Keep cross-module dependencies explicit.
- Use hermetic Lua and local Git fixtures for Lazy startup tests. Do not download plugins during CI.
- Clone Lazy only on explicit opt-in demand. Respect locked revisions and never replace existing checkouts.
- Treat activated plugin managers as restart-only; do not claim rollback of external plugin state.
- Make one owner responsible for each shared task.
- Declare module types, defaults, bounds and descriptions only in the owning `init.lua` LuaDoc.
- Generate `settings.schema.json` from LuaDoc annotations. Do not author module `schema.json` files.
- Use local LuaDoc classes for nested objects and typed arrays. Reject recursive class schemas.
- Preserve global, buffer-local and window-local option scope during migrations.
- Preserve pre-existing Neovim filetype mappings when a feature disables or rolls back.
- Restore prior user key mappings when disabling or rolling back a mapping owner.
- Do not introduce global variables for internal state.
- Preserve commands, mappings and persistent data unless the approved plan changes them.
- Never overwrite a user-owned command. Create settings files only on explicit open.
- Own and reuse Neovim autocommand groups. Do not replay or duplicate event handlers on reload.
- Keep Linux and Windows as equal targets for migrated features.

## Tests

- Add a stored test only when it protects a new behavior contract.
- Require a test to fail when the protected behavior breaks.
- Run throwaway checks freely without committing them.
- Test persisted settings, failure recovery and plugin boundaries through real entry points.
- Reject tests that only compare copied source text or duplicate configuration inventories.
- Run `nvim --headless -u NONE -l tests/schema_spec.lua` for schema changes.
- Run `nvim --headless -u NONE -l scripts/generate_schema.lua --check` for schema changes.
- Run `nvim --headless -u NONE -l scripts/check_legacy_names.lua` after staging source changes.
- Validate saved settings before applying them. Preserve accepted settings when file reading or validation fails.
- On explicit reload, apply only changed option fields so unchanged buffer/window overrides survive.
- Observe only the configured settings path and replace the watcher on repeated setup.
- Run `nvim --headless -u NONE -l tests/settings_spec.lua` after settings changes.
- Run Neovim startup and behavior checks before claiming runtime compatibility.
- Fail required integration checks when dependencies are unavailable.
- Report missing prerequisites and tests that could not execute.

## CI

- Keep the Linux and Windows checks on pushes, pull requests, and a daily default-branch schedule.
- Require schema tests, generated-file checks, legacy-name checks, and headless Neovim smoke tests.
- Add CI checks only for concrete behavior failures not covered by an existing check.
- Run checks on pull requests and pushes to branches.
- Keep release checks in a separate workflow for version tags.
- Match release tags with the complete semantic version format.
- Check out release jobs with full ancestry before testing the tagged commit.
- Protect release tags with a tag ruleset.
- Restrict release credentials to protected release tags.
- Keep CI changes on the default branch before creating a release tag.
- Delete topic branches only after their pull request has merged successfully.
- Run branch cleanup with a same-repository merged-PR guard and no untrusted code checkout.
- Propagate tool failures, including missing prerequisites.
- Test real entry points or isolated fixtures rather than file existence.

## Docs

- Keep each document concise, factual and focused.
- Keep standing rules here, and put implementation records near their source.
- Write US English in active voice and use one instruction per sentence.
- Follow [ASD-STE100](https://www.asd-ste100.org/) sentence guidance.
- Keep instructions within 20 words and descriptions within 25 words where practical.
- Review long sentences and split unrelated facts.
- Use numbered lists for three or more ordered instructions.
- Use bullet lists for long sets or lists of full sentences.
- Translate non-English documents from a reviewed English draft.
- Preserve commands, paths and code in translations.
- Keep user installation and configuration instructions in `README.md`.
- Read [architecture](doc/architecture.md) before changing module boundaries.
- Read [migration](doc/migration.md) before renaming interfaces or moving persistent state.
- Read [settings](doc/settings.md) before changing saved settings or validation behavior.
