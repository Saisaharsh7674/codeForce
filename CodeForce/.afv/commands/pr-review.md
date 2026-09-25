---
name: pr-review
description: "Technical-lead PR review — pull a developer's PR/branch diff and review it for story/requirement correctness, best practices, code optimization, scenario coverage, and the Salesforce coding standards, then produce a verdict with findings"
---

# SFDC CRM — Technical-Lead PR Review

Help the **technical lead** review a developer's changes (a GitHub PR or a feature
branch) on **five dimensions**, not just style:

1. **Story / requirement correctness** — does the code actually do what the user
   story asks, completely and correctly?
2. **Scenario coverage** — are all relevant scenarios handled (happy path, edge
   cases, bulk, negative/error paths, nulls, mixed DML, permissions) and tested?
3. **Best practices & good development** — clean, maintainable, well-structured,
   idiomatic Salesforce code.
4. **Code optimization** — efficient SOQL/DML, governor-limit safety, no needless
   work or round-trips.
5. **Salesforce coding standards** — the checklist embedded below.

The goal is a clear, itemized verdict: what's correct, what's risky or missing, and
what violates a standard — each with file/line references the lead can act on.

**This flow is read-only.** Do **not** edit code, commit, push, deploy, or change
the PR. Only read the diff and report findings. If the lead later wants fixes,
that is a separate action they must explicitly request.

**For every input the flow needs, ask via the interactive question tool
(`ask_user_tool`)** — never a static "reply with your values" prompt. Ask one
field at a time, read the answer back, then proceed.

**Run all `git`/`gh` commands directly in the terminal.** Assume `gh` and `git`
are already authenticated — do **not** run any login/auth step.

Optional pre-filled input from the invocation: `$ARGUMENTS`
(may contain a PR number, branch name, or URL; still confirm it).

## Step 0 — Identify what to review

Detect current state, then confirm the target with `ask_user_tool`:

```
git rev-parse --abbrev-ref HEAD    # current branch
gh pr list --state open --limit 20 # open PRs (author, number, title, branch)
```

Ask `ask_user_tool` how the lead wants to select the review target, with selectable
`answers`:
- **"By PR number"** — free text / suggest one from the `gh pr list` output.
- **"By branch name"** — free text (e.g. `feature/STORY-123`).
- **"Current branch"** — review the branch currently checked out.

If a value was passed in `$ARGUMENTS`, pre-fill it and just confirm.

Then ask (with `ask_user_tool`) for the **base branch** to diff against — selectable
`answers: ["main"]` (default `main`); allow free text for other bases.

### Capture the story / acceptance criteria (needed for correctness review)

You cannot judge whether the code is "written perfectly for the story" without
knowing the story. Gather it with `ask_user_tool`:

- **User story number** — pre-fill from the branch name (`feature/<...>`) or PR title.
- **Story summary / acceptance criteria** — free text. Ask the lead to paste the
  requirement or acceptance criteria. If they don't have it handy, also check the
  PR description (`gh pr view --json body`) and use that as the requirement source,
  then confirm it captures the intent.

If no requirement detail is available at all, say so explicitly and note in the
report that **correctness could only be assessed against the code's apparent
intent, not the actual story** — don't silently skip it.

## Step 1 — Gather the changed files and diff

Resolve the target into a concrete diff. Prefer the PR view when a PR number was given:

```
gh pr view <PR-NUMBER> --json number,title,author,headRefName,baseRefName,files,additions,deletions
gh pr diff <PR-NUMBER>
```

For a branch (or current branch), diff against the base:
```
git fetch origin <BASE_BRANCH>
git diff --name-only origin/<BASE_BRANCH>...<BRANCH>
git diff origin/<BASE_BRANCH>...<BRANCH>
```

List the changed files grouped by metadata type (Apex classes, triggers, LWC, Flows,
custom objects/fields, validation rules, etc.). Read the full content of each changed
file with the file tools (not just the diff hunks) so naming, headers, and structure
can be judged in context. Echo the file list back and confirm before reviewing.

## Step 2 — Story correctness, best practices, optimization & coverage

Before the line-by-line standards pass, step back and review the change **as a
whole** against the story. Record findings as **OK / Concern / Blocker**, each with
a file/line reference and a one-line recommendation.

### 2a. Story / requirement correctness
- Does the diff **implement everything the story asks** — every acceptance criterion?
  Call out any requirement that appears **unimplemented or only partially done**.
- Does it do **only** what the story asks, or is there scope creep / unrelated changes?
- Is the logic **actually correct** for the requirement (right objects, fields,
  filters, conditions, operations)? Trace the main path and confirm it produces the
  intended outcome.
- Are there changes that look like they'd **break existing behavior** (regressions)?

### 2b. Scenario coverage
Think adversarially — what inputs/states could this code hit? For the changed logic,
check whether these are handled **and tested**, and list any that are missing:
- **Happy path** and the main alternate paths.
- **Bulk / volume** — collections, ≥ 200 records, trigger bulk invocation.
- **Negative / error paths** — exceptions, failed DML, callout failures, validation errors.
- **Boundary & null** — empty lists, null fields, zero/large values, missing related records.
- **Mixed operations** — insert+update, partial success (`Database.*` with `allOrNone=false`).
- **Permissions / sharing** — different user contexts, FLS/CRUD, `runAs`.
- **Idempotency / recursion** — re-entry, duplicate events, recursive trigger guards.
- **Test assertions** — do tests actually **assert outcomes** (not just run code for
  coverage)? Is coverage meaningful, not padded?

### 2c. Best practices & good development
- Clear structure and separation of concerns (trigger → handler → service/util).
- Readable, self-documenting names; reasonable method/class size; no dead or duplicated code.
- Reuse of existing utilities/patterns in this repo instead of reinventing.
- Proper error handling and logging; no swallowed exceptions.
- No anti-patterns (business logic in triggers, hardcoded values, God classes).

### 2d. Code optimization & performance
- SOQL/DML **outside loops**; queries selective and only needed fields/rows; `LIMIT`/pagination.
- Governor-limit headroom for bulk; no redundant queries (query once, reuse maps).
- Efficient collections (Maps/Sets over nested loops); caching where appropriate.
- On LWC: no unnecessary server round-trips; `cacheable=true` for idempotent reads; LDS where possible.

> Use judgment here — these are quality signals, not a rigid checklist. Flag what a
> senior reviewer would raise; don't nitpick trivialities.

## Step 3 — Review against the Salesforce Coding Standards

Go through every changed file and evaluate it against the checklist below. Only apply
the categories relevant to each file's type (don't flag LWC rules on an Apex class).
For each item, record **Pass / Violation / N/A**, and for every violation cite the
**file and line** plus a one-line fix suggestion.

### Naming & structure
- Custom field **API names** follow the org's agreed naming convention (consistent, meaningful; apply any project-specific prefix if one is in use).
- Every created component has a **description**.
- Classes/triggers/components use the naming conventions below.
- Custom objects & custom fields contain **no underscores** in the middle (names);
  custom object names are **unique, singular, uppercase-initial**.
- Acronyms/abbreviations limited for objects & fields.
- Lightning app names: unique, lowercase-initial, suffix **`App`**; components suffix **`Cmp`**.
- Lightning event names: lowercase-initial, suffix **`Evt`**.
- Visualforce page names: uppercase-initial, no underscores/spaces, CamelCase.
- **Apex class names**: uppercase-initial, CamelCase, no underscores/spaces. Suffixes —
  custom controller `_CC`, controller extension `_CX`, batch `_Batch`, schedulable
  batch `_BatchSchedule`, **test class `<ClassName>_Test`**.
- **Triggers**: `[Object][Operation]Trigger` or `[Object]Trigger`; **one trigger per
  object** (single trigger, all operations).
- **Apex methods**: verbs, lowerCamelCase.
- **Apex variables**: lowerCamelCase, short but meaningful; avoid one-char names except throwaways.
- **Apex constants**: `ALL_UPPER_WITH_UNDERSCORES`; common constants in `GlobalConstants`;
  keep scope minimal (private preferred); record-type/field-value constants in `GlobalConstants`.
- Public Group/Queue names prefixed with the app (e.g. `Mosaic_Complaints`); app prefix
  reused across LWC/Aura/Apex/Flow when multiple apps exist.
- **No Process Builder / Workflow rules** (use Flow).
- Validation rule names: unique, uppercase-initial, whole words.

### Data model
- Accounts for data-growth projections; big objects for large audit/security volumes.
- Minimize fields per object; watch **data skew** and **junction-object volume**;
  minimize master-detail; prefer normalized tables; customer data in standard
  Account/Contact; prefer standard objects; ensure indexed fields; prefer record
  types over picklists where indexing matters.

### Apex — access, size, comments
- Classes use **`with sharing`** (unless deliberately not).
- CRUD/FLS checks via `isAccessible/isCreateable/isUpdateable` (Schema describe).
- Classes **< 200 lines**; methods **< 60 lines**; refactor into utility/helper classes.
- **Header comment block** on every file (class name, purpose, created date, author).
- Every method commented (purpose, params, return); inline comments where logic is non-obvious.
- Reusable code in Utility classes; string literals/constants in Global Constant class.

### Apex — SOQL / DML / governor limits / security
- **No SOQL/DML inside loops**; use SOQL for-loop for large sets.
- Selective SOQL filters; avoid querying formula fields; use `LIMIT`.
- **`WITH SECURITY_ENFORCED`** for FLS in SOQL.
- Use `Limits` class methods to guard governor limits.
- **No hard-coded IDs/URLs**; use Custom Metadata (avoid custom labels/settings for this).
- **No SOQL injection** — prefer static queries + bind variables; if dynamic,
  `String.escapeSingleQuotes()` on user input.

### Triggers
- All triggers **bulkified** and test classes prove bulkification (**≥ 20 records**).
- **One trigger per object**; logic delegated to handler/dispatcher framework.
- Triggers toggleable via custom setting/metadata + static variable.
- Recursion guarded; only one-liner delegation inside the trigger.

### Test classes
- **> 95% coverage.**
- `System.runAs` for user contexts; **test data factory** (no `SeeAllData=true` — build own data).
- `Test.startTest()/stopTest()`; `System.assert*` to prove behavior.
- Bulk tests with **≥ 20 records**; static resources for callout JSON; `HttpCalloutMock` for callouts.

### Lightning Web Components
- Standard **base LWC components** only; no raw HTML unless no base component exists.
- No server round-trips to sort/filter data already on the client.
- DOM via JS + event listeners (no full-page reload); **spinner** while loading.
- **LDS** for create/update and for list views/metadata/picklists (no Apex for those).
- Lazy-load with `<lightning-tabset>`/`<lightning-tab>`; `@AuraEnabled(cacheable=true)`
  for idempotent, non-mutating reads.
- **SLDS** styling, no custom stylesheets/inline CSS (use a `.css` in the bundle).
- Apex only for complex logic; pass data between components via attributes/events/methods;
  limit queried fields/rows, set `LIMIT`, paginate large sets.
- Minimal third-party JS; load libs from **static resources**, not CDNs.
- `getRecord` wire adapter requesting only needed fields; UI API when LDS not feasible.

### Process automation (Flow)
- **No hard-coded IDs** in Flows/Process Builder.
- Batch DML at the end of the flow; **no query/DML inside Loop elements** (assign in
  loop, update outside).
- One master Flow per object (insert/update); invocable sub-processes for actions.

## Step 4 — Produce the review report

Summarize into a single verdict covering **all five dimensions**. Structure:

```
# PR Review — <PR # / branch>  (base: <BASE_BRANCH>)
Author: <author>   Story: <USER-STORY-NO>   Files: <n>   +<additions> / -<deletions>

## Verdict: <Approve / Changes requested / Blocked>
<one-line rationale>

## 1. Story correctness
- Requirements met: <yes / partial / no> — <notes>
- Gaps / missing requirements: <list or "none">
- Scope creep / unrelated changes: <list or "none">

## 2. Scenario coverage
- Covered: <list>
- Missing / untested scenarios: <list — these are usually the most important findings>

## 3. Best practices & optimization
- Concerns: [<category>] <file>:<line> — <issue> → <recommendation>

## 4. Coding-standard violations ( <count> )
1. [<category>] <file>:<line> — <what's wrong> → <suggested fix>
2. ...

## Passed / OK
- <short notes on what's solid>

## Not applicable
- <category>: <why>
```

Order findings by severity — **correctness blockers and missing scenario coverage
first**, then security/governor-limit/bulkification, then best-practice concerns,
then naming/comments/style. Be specific: always cite file and line, and keep each
recommendation to one line. If any dimension couldn't be fully assessed (e.g. no
story detail), say so rather than implying it passed.

## Step 5 — Optional: post as PR feedback

Only if the target was a PR **and** the lead explicitly asks. Ask with `ask_user_tool`
`answers: ["Post as PR comment", "Just show me the report"]` (default: just show).

If they choose to post, write the report to a temp file and:
```
gh pr comment <PR-NUMBER> --body-file <tmpfile>
```
Confirm the comment URL. Do **not** approve, request-changes via review, merge, or
label the PR unless the lead separately and explicitly asks.

## Guardrails

- **Read-only.** Never edit, commit, push, deploy, or change PR state during the review.
- Run all commands in the terminal; assume `gh`/`git` are already authenticated — no login step.
- Confirm the review target, story context, and file list before reviewing.
- Review all five dimensions — correctness, coverage, best practices, optimization,
  standards — not just the coding-standards checklist.
- Apply only the checklist categories relevant to each file's metadata type.
- Every finding must cite a file and line; never report one you can't point to.
- Do not fabricate standards or requirements — evaluate against the checklist above
  and the story the lead provides; if a dimension can't be assessed, say so.
- Distinguish severity: a correctness/coverage gap is a blocker; a naming nit is not.
- If a `git`/`gh` command fails, stop and surface the error; do not retry destructively.
