# Contributing to ChoscorUsage

Anyone is welcome to create an issue to report a bug or suggest a change.
ChoscorUsage does not accept external pull requests. The maintainer implements
changes and opens any pull requests needed for the project.

When reporting a problem with usage numbers, never paste tokens, `auth.json`,
`.credentials.json`, Keychain contents or raw endpoint responses. Describe the plan,
the window that looks wrong, and what the CLI itself reports.

## Maintainer pull request title and description

Keep changes small enough to explain and verify independently, include
behavior-focused tests, and avoid unrelated cleanup. One approving review is not
required while the project has a single maintainer; the automated quality gates
are the required review surface.

Use a specific, action-oriented title. The preferred format is
`<type>(<scope>): <imperative summary>`, matching the project's Conventional
Commit subjects, for example `fix(codex): fall back to session logs on HTTP 502`.
The title should make sense when skimmed in a PR list or release history.

The [PR template](.github/pull_request_template.md) prompts for the reason,
meaningful changes, verification, and any context a reviewer cannot see in the
diff. State exact checks run and their outcomes; explain relevant checks that
were blocked or not run. Add screenshots for visible UI changes when useful.
Link an issue if one exists; use `Closes #N` only when the PR fully resolves it.

## Before submitting a maintainer change

Install Xcode 26, Python 3.12+, actionlint 1.7.7, and the dependencies in
`scripts/ci/requirements.txt`. SwiftLint is not installed from Homebrew: the
pinned, checksum-verified binary is downloaded into `build/tools/`. Any missing-tool
message includes the installation command. Run:

```sh
python scripts/ci/quality.py swiftlint-install
python scripts/ci/quality.py format
python scripts/ci/quality.py fast
```

For app, Xcode project or package API changes, run the full suite:

```sh
python scripts/ci/quality.py full
```

Focused stages are documented in `docs/CI.md`. The checked-in commands and CI
are canonical.

## Size, structure and comments

SwiftLint enforces strict limits as errors: 400 lines per file, 40 lines per
function body, 250 lines per type body, 120 characters per line, cyclomatic
complexity 10, nesting depth 2 and 5 parameters. Split code by responsibility
before reaching a limit; for SwiftUI, extract small subviews. Do not meet a limit
by compressing formatting or removing useful comments.

- One primary type per file, named after the type, grouped in feature folders.
  No `Utils`, `Helpers` or `Misc` files.
- Every Swift file starts with a one- or two-line `//` comment saying what it owns.
- Every public package declaration has a `///` comment stating its contract:
  inputs, outputs, errors, and the thread or actor it runs on.
- Comments explain *why* (constraints, protocol quirks, tradeoffs), not what the
  code does. Undocumented endpoints, headers and Keychain naming rules are
  documented where they are used, with a source link and the date verified.
- No commented-out code. A TODO references an issue: `TODO(#12): …`.

## Exceptions and suppressions

Fix lint and analyzer findings rather than suppressing them. A suppression must
name exactly one rule on the next line and state why the code is correct:
`// swiftlint:disable:next <rule> - <reason>`. File-wide disables, `all`, and
disables without a reason fail the `swiftlint` stage. Never raise a size limit to
make code fit.

Never weaken a test to hide a race. Test retries and timeout-only fixes are not
accepted. If a gate is temporarily removed, document the precise reason and
tracking issue.

## Scope of evidence

CI builds and runs unit tests; it does not show the menu bar, its menu, Keychain
prompts or notifications. Visual and end-to-end behavior is checked by running the
app with real profiles, and PRs say which was done.
