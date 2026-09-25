---
name: pr-flow
description: "Interactive Git + GitHub PR flow — branch, commit, push, validate against the org, and raise a PR (generic, prompts for all inputs)"
---

# SFDC CRM — Git & GitHub PR Flow

Guide the user through the feature-branch → validate → PR process for the
`Saisaharsh7674/codeForce` repo. Nothing is hardcoded — collect every value from the user
before running commands. Confirm the plan before any push, deploy/validate, or PR step.

**This flow supports two entry modes (chosen in Step 0):**
- **"I've already made my changes"** — the usual case. The developer already
  created their feature branch and finished all development; the flow only
  commits, generates the manifest, pushes, raises the PR, and validates last.
  Steps 1 and 1a (branch creation and making/pulling components) are skipped.
- **"Start a new branch"** — greenfield. The flow also creates the branch (Step 1)
  and helps make/pull components (Step 1a) before committing.

**For every input the flow needs, ask via the interactive question tool
(`ask_user_tool`) — never render the inputs as a static markdown table or a
"reply with your values" prose prompt.** For each field call `ask_user_tool` with
a `question` (the label plus its default/example) and, for fixed-option fields,
an `answers` list so the options render as clickable choices. Free-text fields
offer their default/example as a suggested answer and let the user type their own.
Ask one field at a time, read each answer back, then proceed. This applies to
every step that requires input (Step 0, and the file/source/reviewer/label
prompts in Steps 2, 3, and 6).

**Run every command in this flow directly in the terminal.** All `git`, `sf`, and
`gh` commands below are executed in the terminal. Assume the CLIs are already
authenticated — do **not** run any authentication/login step (`sf org login`,
`gh auth login`, etc.) and do **not** verify org authorization. The target org and
GitHub are already connected.

Optional pre-filled input from the invocation: `$ARGUMENTS`
(may contain the user story number and/or a short description; still confirm it).

## Reference: Release tracks

| Track           | Development branch (base) |
|-----------------|---------------------------|
| Main            | `main`                    |

The **target org is no longer derived from the track**. The flow lists every
connected org (`sf org list`) and the user selects the Developer Org to retrieve
from and validate against (see Step 0b, item 5). Deploys remain check-only.

Feature branch pattern:
- `feature/<USER-STORY-NO>` (e.g. `feature/STORY-123`)

## Step 0 — Pick the entry mode

First, figure out where the developer already is — most of the time they have
**already created a branch and finished their changes**, and only want to
push + raise the PR. Don't assume a fresh start.

Detect the current state, then confirm the mode with `ask_user_tool`:

```
git rev-parse --abbrev-ref HEAD   # current branch
git status --porcelain            # uncommitted changes
```

Ask `ask_user_tool` with selectable `answers`:
- **"I've already made my changes"** — the common case. The branch exists and the
  work is done; skip branch creation and the change/pull step. Go straight to
  Step 0b (gather the remaining inputs) → Step 2 (commit) onward.
- **"Start a new branch"** — greenfield. Run Step 0b, then Step 1 (create branch)
  and Step 1a (make/pull components) before committing.

If the current branch is already a `feature/...` branch and there are uncommitted
changes, default the selection to **"I've already made my changes."**

## Step 0b — Gather the remaining inputs (use `ask_user_tool`, don't assume)

Collect values with the interactive `ask_user_tool` — **not** a static table or a
"reply with your values" message. Pre-fill from `$ARGUMENTS`, and in "already made
my changes" mode **derive from git instead of asking** wherever possible:

1. **Release track** — always ask; selectable `answers: ["main"]`. Sets BASE_BRANCH from the table above. The org is chosen separately below (Developer Org), not from the track.
2. **User story number** — in "existing" mode, infer from the current branch name (`feature/<...>`) and confirm; in "new branch" mode, free text (suggest `STORY-123`). Used in branch/commit/PR title.
3. **Short description** — free text; one line for the commit/PR title.
4. **Files to stage** — in "existing" mode, default to everything already changed (`git status --porcelain`) and show it for confirmation; otherwise free text (paths under `force-app/main/default/...`, or `.` for all — confirm explicitly if `.`).
5. **Target org (Developer Org)** — do **not** default to any hardcoded org. Instead, **list every connected org and let the user select one.** Run `sf org list --json` (or `sf org list`) to enumerate all authenticated orgs, then call `ask_user_tool` with the org aliases/usernames as selectable `answers` so the user picks the Developer Org to use (e.g. `sivva.sai-saharsh@capgemini.com2026_09_24_13-58-37.demo`). Use the picked org as `TARGET_ORG` for the org-compare retrieve (Step 1b) and the final deploy/validate (Step 7). The retrieve and validate are still safe/read-only against whichever org is chosen.
6. **PR reviewer(s)** — **required**, and the flow must support **more than one**. The `ask_user_tool` popup only allows a **single** selection per prompt, so collect reviewers with a **repeat loop** rather than one multi-select prompt:
   1. Ask with `ask_user_tool` using `answers: ["Saisaharsh7674"]` (also allow the user to type another GitHub username). Add the chosen reviewer to the list.
   2. Then ask "Add another reviewer?" with `answers: ["Add another reviewer", "Done"]` (drop already-picked names from the options). If they pick "Add another reviewer", repeat step 1; if "Done", stop.
   3. Keep looping until the user is done, and do not proceed until **at least one** reviewer has been collected.
   Collect the picks into a comma-separated list for the `--add-reviewer` command in Step 5.
7. **PR label(s)** — **required**; suggest `ready-for-review`.

Derive `BRANCH`:
- "existing" mode → the current branch (from `git rev-parse --abbrev-ref HEAD`).
- "new branch" mode → `feature/<USER-STORY-NO>`.

Echo back the resolved values (mode, track, base branch, target Developer Org, branch name, files, reviewers, labels) and ask the user to confirm before running anything.

## Step 1 — Sync and create the branch *(new-branch mode only)*

Skip this step entirely in "I've already made my changes" mode — the branch
already exists. Only run it when the user chose "Start a new branch":

```
git checkout <BASE_BRANCH>
git pull origin <BASE_BRANCH>
git checkout -b <BRANCH>
git push -u origin <BRANCH>
```

If the branch already exists locally, check it out instead of `-b` and offer to merge in the latest base:
```
git checkout <BRANCH>
git fetch origin
git merge origin/<BASE_BRANCH>
```
If merge conflicts occur, stop and ask the user to resolve; do not force anything.

In "existing" mode, instead just verify the current branch is a feature branch
(not `main` or another base branch); if the developer is somehow on the base
branch, stop and warn — never commit development directly to `<BASE_BRANCH>`.

## Step 1a — Make component changes / pull components *(new-branch mode only)*

Skip this step in "I've already made my changes" mode — the work is done. Only
run it in "new branch" mode. Ask with `ask_user_tool` whether they will (a) edit
the components locally themselves, or (b) have you retrieve (pull) specific
components from the org first — offer selectable
`answers: ["I'll edit locally", "Pull components from the org"]`.

- If they choose to edit locally, pause and let them make their changes; continue
  to Step 2 only after they confirm they are done.
- If they want components pulled, ask with `ask_user_tool` **which components to
  pull** (free text — component names, metadata types, or paths, e.g.
  `ApexClass:MyClass`, `LWC:myComponent`, or `force-app/main/default/classes`),
  then retrieve them from the user-selected Developer Org (`TARGET_ORG`):

```
sf project retrieve start --metadata <component>[ --metadata <component>...] --target-org <TARGET_ORG>
```

  (or `--source-dir <path>` when given paths). Report what was retrieved, then
  let the user make further edits before continuing. Only proceed to Step 2 once
  the user confirms all component changes are complete.

## Step 1b — Retrieve from the org and compare (both modes)

Before staging anything, reconcile the local working tree against the org so the
developer knows whether the org holds changes they don't have locally. Run this
in **both** entry modes.

1. Determine the components that changed locally — from `git status --porcelain`
   and `git diff --name-only <BASE_BRANCH>...<BRANCH>` under `force-app/`.
2. Retrieve those same components from the **user-selected Developer Org**
   (`TARGET_ORG` from Step 0b) into a **temporary/throwaway location** so the
   local working files are never overwritten:

```
sf project retrieve start --manifest manifest/package.xml --target-org <TARGET_ORG> --output-dir .pr-flow-org-compare
```

   (or retrieve by `--metadata <component>` / `--source-dir <path>` for the
   specific changed components). If the manifest doesn't exist yet, build the
   changed-component list first (same mapping as Step 2a).
3. Compare the retrieved org copy against the local files (e.g. `git diff --no-index
   <local-path> .pr-flow-org-compare/<same-path>` per changed component).
4. **If the org has extra changes** — differences that are not part of the
   developer's local changes (someone else modified the component in the org, or
   the org is ahead) — **inform the user**: list each component and summarize the
   extra org-side changes. Ask the user how to proceed with `ask_user_tool`
   (e.g. review and merge the org changes locally, or continue as-is), then
   **go to the next process (Step 2)**.
5. If there are no extra org changes, say so and continue to Step 2.

Clean up the temporary compare directory (`.pr-flow-org-compare`) afterward, and
never stage or commit it.

## Step 2 — Stage and commit

```
git status
git add <files-from-input>
git commit -m "<USER-STORY-NO>: <description>"
```
Use the exact files the user provided. If the files-to-stage value wasn't
captured in Step 0, ask for it with `ask_user_tool` (suggest
`force-app/main/default/...` or `.` for all). Never `git add .` without explicit confirmation.

## Step 2a — Generate the package.xml manifest

Build `/home/codebuilder/codeForce/CodeForce/manifest/package.xml` listing **all the
components that changed** in this branch. Determine them from what was
committed/staged in Step 2 (e.g. `git diff --name-only <BASE_BRANCH>...<BRANCH>`
under `force-app/`), group each member under its metadata type, and write the
manifest. This same manifest is reused to post as a PR comment (Step 4) and to
run validation (Step 7, the final step).

Format: one `<types>` block per metadata type, a `<members>` entry per component
(the component API name, not the file path), and keep `<version>67.0</version>`.
Example shape:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>MyApexClass</members>
        <members>MyApexClassTest</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>myComponent</members>
        <name>LightningComponentBundle</name>
    </types>
    <version>67.0</version>
</Package>
```

Map file paths to metadata types and member names as usual (e.g.
`classes/*.cls` → `ApexClass`, `lwc/<name>/` → `LightningComponentBundle`,
`bots/<name>/` → `Bot`, `aiPlannerBundles/<name>/` → `GenAiPlannerBundle`, etc.).
Write the file with the file tools (overwrite the existing manifest), then show
the user the resulting `package.xml` and confirm it before continuing.

**Do not stage, commit, or push `package.xml`** — it is only used to post as a PR
comment (Step 4) and to run validation (Step 7). If it appears in `git status`,
leave it unstaged.

## Step 3 — Push the final branch

```
git push origin <BRANCH>
```

## Step 4 — Open the PR

Build the PR body from this template (fill in from the collected inputs; leave TODOs where the user hasn't provided detail):

```
## Summary
- <what changed>
- <why>

## Jira User Story
<USER-STORY-NO> — link or description

## Deployment Notes
<deploy order, pre/post steps, permission sets, etc.>
```

Create the PR (write the body to a temp file and pass with `--body-file`):
```
gh pr create --base <BASE_BRANCH> --head <BRANCH> --title "<USER-STORY-NO>: <description>" --body-file <tmpfile>
```
Report the PR URL/number returned.

Then post the generated `manifest/package.xml` (from Step 2a) as a **PR comment**
so reviewers can see the full component list — the manifest is never committed or
pushed, only added as a comment. Write the comment body to a temp file wrapping
the manifest in a fenced ```xml block, then:

```
gh pr comment <PR-NUMBER> --body-file <tmpfile>
```

The comment body should look like:

````
### Deployed components (package.xml)
```xml
<contents of manifest/package.xml>
```
````

Confirm the comment was posted.

## Step 5 — Reviewers & labels (if provided)

If reviewers weren't captured in Step 0, ask for them with `ask_user_tool` —
reviewers are **required** and the flow must support **more than one**. Since the
popup only allows one selection at a time, use the same **repeat loop** as Step 0b:
ask for one reviewer from `answers: ["Saisaharsh7674"]` (plus free text),
then ask "Add another reviewer?" (`answers: ["Add another reviewer", "Done"]`),
repeating until the user is done — and keep asking until at least one is provided.
Combine the picks into a comma-separated list for `--add-reviewer`.
Labels remain optional (suggest `ready-for-review`); skip the label command if left empty.

```
gh pr edit <PR-NUMBER> --add-reviewer <username>[,<username>...]
gh pr edit <PR-NUMBER> --add-label "<label>"
```

## Step 6 — Technical review label

Add the review-status label. Ask with `ask_user_tool`, offering selectable
`answers: ["Pending Technical Review - Digital Nexus"]` (let the user type
another label if needed). Skip if left empty.

```
gh pr edit <PR-NUMBER> --add-label "Pending Technical Review - Digital Nexus"
```

## Step 7 — Validate against the org (check-only, final step)

As the **last** step — after the branch is pushed and the PR is raised — run a
validation-only deploy against the **user-selected Developer Org** (`TARGET_ORG`
from Step 0b) **using the same `manifest/package.xml` generated in Step 2a**. This
does NOT deploy:

```
sf project deploy validate --manifest manifest/package.xml --target-org <TARGET_ORG> --test-level RunLocalTests
```

Report the result. If validation fails, stop, summarize the errors, and let the
user fix before continuing. The PR is already open — flag on the PR that
validation failed and do not mark it ready until it passes, unless the user
explicitly says otherwise.

**Once validation completes and is successful, capture the success results as a
screenshot.** Take a screenshot of the successful validation output (the terminal
result showing status `Succeeded` / all tests passing, plus the deploy/validation
ID), save it under `/home/codebuilder/codeForce/CodeForce/docs/validation/` with a
descriptive name (e.g. `<USER-STORY-NO>-validation-success.png`), and note its
path. Ask the user to provide/confirm the screenshot if it can't be captured
automatically.

Then post the **successful validation screenshot** as a PR comment so reviewers
can see the validation succeeded. Write the comment body to a temp file embedding
the image with markdown (`![Validation success](<path-or-uploaded-url>)`) and post
it:

```
gh pr comment <PR-NUMBER> --body-file <tmpfile>
```

The comment body should look like:

```
### Validation success

Check-only validation against `<TARGET_ORG>` succeeded (RunLocalTests passed).

![Validation success](<path-or-uploaded-image-url>)
```

Confirm the screenshot comment was posted.

## Guardrails

- Run all commands in the terminal. Do not perform any authentication/login or org-authorization step — assume `sf` and `gh` are already authenticated.
- Confirm resolved inputs before Step 1, and again before the PR is actually created.
- Never commit directly to `<BASE_BRANCH>`; always work on the feature branch.
- Never force-push, reset --hard, or delete branches unless the user explicitly asks.
- Do not merge the PR — merges are done in GitHub after approval (Merge commit, ≥1 approval).
- If any git/sf/gh command fails, stop and surface the error; do not retry destructively.
- Treat the validation deploy as check-only; never run a real `sf project deploy start` in this flow.
