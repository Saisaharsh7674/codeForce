---
name: gen-docs
description: "Generate delivery documents — Impact Analysis for a story, or RCA + Solution + Impact Analysis for a defect — as Word (.docx) files"
---

# SFDC CRM — Delivery Document Generator

Generate the delivery Word documents for the work in hand by filling a JSON
spec and running the stdlib generator at `.claude/scripts/docgen.py`. **Never
hand-write the `.docx`** — always go through the generator so the formatting
matches the approved templates. The generator depends only on the Python
standard library (no pip installs).

**Collect every input the flow needs via the interactive question tool
(`ask_user_tool`) — never render inputs as a static markdown table or a "reply
with your values" prose prompt.** For each field call `ask_user_tool` with a
`question` (the label plus its default/example) and, for fixed-option fields, an
`answers` list so the options render as clickable choices. Ask one field at a
time, read each answer back, then proceed. Derive from git wherever possible
before asking.

Optional pre-filled input from the invocation: `$ARGUMENTS`
(may contain the Jira/incident id and/or a short description; still confirm it).

## Handling attachments

The primary input on both paths — the **requirement** (story) and the **defect
summary** (defect) — accepts a text box **and/or an attachment**. When the user
supplies an attachment:

- They give you a **file path** (drag-drop / paste path, or `$ARGUMENTS`). Read
  it with the `Read` tool, which handles text, PDFs (use the `pages` arg for
  long ones), and images (screenshots of tickets/errors are read visually).
- Treat the attachment's contents as part of that field — extract the relevant
  requirement/symptom text and **read it back to the user** so they can confirm
  or correct before you investigate the code.
- The text box and attachment are complementary: the user may provide one, the
  other, or both. If both are given, merge them. If neither is usable (e.g. an
  unreadable path), say so and ask again.
- If a path doesn't exist or can't be read, tell the user the exact path that
  failed and ask them to re-attach or paste the text instead — never guess the
  contents.

## Document sets

- **Developer / user story** → one **Impact Analysis** document (`type: "impact"`).
- **Support / defect** → three documents: **RCA** (`type: "rca"`),
  **Solution Document** (`type: "solution"`), and **Impact Analysis**
  (`type: "impact"`).

## Step 0 — Pick the mode

Detect context first (current branch, `$ARGUMENTS`), then confirm with
`ask_user_tool` using selectable `answers`:
- **"Developer — user story (Impact Analysis only)"**
- **"Support — defect (RCA + Solution + Impact Analysis)"**

If the branch/id looks like a defect (INC…) lean defect; if it looks like a
story (a `feature/…` branch or a story/ticket id) lean story — but always
confirm.

---

# Path A — Support / defect (RCA + Solution + Impact Analysis)

For a defect the flow's **first job is to understand the issue, then actually
investigate the code to find the root cause** — do not ask the user to hand you
the RCA. You derive it from the components, then confirm it, then generate all
three documents.

## A1 — Ask for the issue first

Before anything else, use `ask_user_tool` to gather the problem statement. Ask
one at a time, pre-filling from `$ARGUMENTS` where possible:
1. **Incident / defect id** — free text (suggest the value from the branch/`$ARGUMENTS`).
2. **Defect summary — what is going wrong?** — the symptom as reported. Accept
   **either** free text in the text box **or an attachment** (a file path to a
   ticket export, screenshot, log, or document). Tell the user they can paste the
   summary *and/or* point you at a file. If they give a path, read it with the
   `Read` tool (it handles text, PDFs, and images) and fold its contents into the
   defect summary before continuing. See **Handling attachments** below.
3. **Expected vs. actual behavior** — free text.
4. **Which component(s) are involved?** — free text (Apex class, Flow, trigger,
   LWC, object, etc.). If the user doesn't know, tell them you'll locate the
   likely components from the symptom in the next step.
5. **Any error message / debug log / example record** — free text, optional but
   very useful for the RCA.

Read the answers back so the user can correct them before you dig in.

## A2 — Investigate the code and find the RCA

Now do the actual root-cause analysis against this repo. **This is analysis
work, not data entry — read the real code.**

1. **Locate the components.** Use `Grep`/`Glob`/`Read` (and the `Explore` agent
   for anything broad) to find the named components under `force-app/`. If the
   user couldn't name them, search by the symptom (error text, object name,
   field, flow name) to identify the likely culprits.
2. **Read the implementation.** Open the relevant Apex classes/triggers/flows,
   follow the call chain (trigger → handler → helper, or flow → action), and
   understand the execution context (before/after, sync/async/future, order of
   operations, governor limits, sharing).
3. **Form the root cause.** Explain *why* the symptom happens in terms of the
   actual code path — e.g. a missing parameter on a flow action, a race
   condition between async execution and platform behavior, a bulkification/
   recursion/order-of-execution issue, a null/limit problem. Cite the specific
   file and line(s) (`path:line`).
4. **Check environment sensitivity** where relevant (does it reproduce only in
   PROD vs UAT? timing/data-volume dependent?).
5. **Propose the fix** and the components that must change.

Then **present your RCA findings to the user for confirmation** (root cause,
evidence, proposed fix, components to change). Use `ask_user_tool` to confirm or
let them correct before you write documents. Do **not** proceed to generation on
an unconfirmed RCA.

## A3 — Fill remaining document fields with `ask_user_tool`

Most content now comes from A1 + A2. Ask only for what's still missing, one at a
time; derive from git/investigation wherever possible:
- **Reported date** (suggest today), **Severity** (`answers: ["High","Medium","Low"]`).
- **Developer**, **Reviewer** (suggest `GeddiViswanathan Duvaragan`), **Date** (suggest today).
- **Business impact** — free text (who/what is affected operationally).
- **Impacted profiles** — capture any that are Y (default N for all standard profiles); offer the standard list as selectable answers and loop "Add another / Done".
- **Impacted permission sets** — free text list (optional).
- **Impacted integrations** — capture any that are Y (default N).

Map the **components to change** (from A2) to component name + metadata type for
the Solution "solution_items"/"components_impacted" and the Impact Analysis
"components" (e.g. `classes/*.cls` → Apex Class, `flows/*.flow-meta.xml` → Flow,
`lwc/<name>/` → LWC, `bots/<name>/` → Bot).

Echo the full resolved picture back and confirm before generating.

Skip to **Step 3 — Write the spec** (build a `"documents": [rca, solution, impact]` set).

---

# Path B — Developer / user story (Impact Analysis only)

Like the defect path, this is **requirements-driven**: the user pastes the story
requirements, then you analyze the codebase to work out **which components need
to change**, ask clarifying questions where the requirement is ambiguous, and
only then build the Impact Analysis.

## B1 — Ask for the story requirements first

Use `ask_user_tool` to collect the story, one at a time (pre-fill from `$ARGUMENTS`):
1. **Jira / story id** — infer from the branch name and confirm.
2. **Requirement — the user story / requirements** — the acceptance criteria,
   description, or full story text. This is the primary input. Accept **either**
   free text in the text box **or an attachment** (a file path to the story
   export, requirements doc, screenshot, or spec). Tell the user they can paste
   the requirement *and/or* point you at a file, and to give you as much as they
   have. If they give a path, read it with the `Read` tool (it handles text,
   PDFs, and images) and fold its contents into the requirement before
   continuing. See **Handling attachments** below.

## B2 — Analyze the codebase to find the components that need to change

From the pasted requirements, work out what has to change in **this** repo.
**This is analysis — read the real code, don't guess.**

1. **Identify the touch points.** Pull the objects, fields, flows, classes,
   triggers, LWCs, permission sets, or UI named or implied by the requirement.
2. **Locate them** under `force-app/` with `Grep`/`Glob`/`Read` (use the
   `Explore` agent for anything broad — e.g. "everything that writes to
   Opportunity Team Member" or "where is this validation enforced").
3. **Trace impact.** Follow the call chain (trigger → handler → helper, flow →
   action, LWC → Apex controller) to find every component that must change or is
   affected downstream, and note the metadata type of each (`path:line`).
4. **Also fold in any work already in progress** on the branch:
   ```
   git rev-parse --abbrev-ref HEAD          # branch → story id
   git status --porcelain                    # uncommitted work
   git diff --name-only main...HEAD          # changed files this branch
   ```
   Map changed files to component name + metadata type (`classes/*.cls` → Apex
   Class, `flows/*.flow-meta.xml` → Flow, `lwc/<name>/` → LWC, `bots/<name>/` →
   Bot, `objects/.../fields/*` → Custom Field, etc.).

**Ask clarifying questions** with `ask_user_tool` wherever the requirement is
ambiguous or maps to more than one plausible component (e.g. "The requirement
says 'update the approval process' — is that the `OpportunityTeamApprovalwithCase`
flow or the Apex approval handler?"). Don't invent scope you can't ground in the
code or the requirement.

Then **present the proposed change list** (component name, metadata type, why it
changes, `path:line`) and confirm with the user before generating.

## B3 — Fill remaining document fields with `ask_user_tool`

Most content now comes from B1 + B2. Ask only for what's still missing, one at a
time:
1. **Title** — one line (suggest one derived from the requirement).
2. **Developer**, **Reviewer** (suggest `GeddiViswanathan Duvaragan`), **Date** (suggest today).
3. **Brief description** — derive from the requirement; confirm.
4. **Executive summary** — what will change and why (derive from B2; confirm).
5. **Scope** — suggest "There will be no downstream impact on any system with these changes." (adjust if B2 found downstream impact).
6. **Impacted profiles** — capture any that are Y (default N); offer the standard list and loop "Add another / Done".
7. **Impacted permission sets** — free text list (optional; pre-fill any found in B2).
8. **Impacted integrations** — capture any that are Y (default N).

The **`components`** for the Impact Analysis come from your confirmed B2 list.
Echo the full resolved picture back and confirm before generating.

## Step 3 — Write the spec

Create `docs/generated/<id>-spec.json` with the file tools. Use
`.claude/scripts/samples/story-example.json` and
`.claude/scripts/samples/defect-example.json` as the schema reference — every
field they show is supported.

- **Story (Path B)** → a single object with `"type": "impact"`. `components` come
  from the confirmed B2 change list; `executive_summary`/`brief_description` from
  the requirement; profiles/permission-sets/integrations from B3.
- **Defect (Path A)** → an object with `"documents": [ <rca>, <solution>, <impact> ]`,
  populated from the investigation:
  - **rca** — `issue_description`, `impact`, `severity`, `reported_date` from A1/A3;
    `root_cause`, `what_happened`, `why_it_happened`, `summary`, `proposed_solution`,
    `expected_outcome` from your A2 findings (cite `path:line` evidence in
    `why_it_happened`/`summary`).
  - **solution** — `description`/`expected_result`/`actual_result` from A1;
    `root_cause`, `resolution`, `solution_items`, `components_impacted` from A2.
  - **impact** — `components` (to change), `executive_summary` (the fix),
    profiles/permission-sets/integrations from A3.

Only include fields you actually have; the generator supplies sensible defaults
and the full standard **Profiles** and **Integration Systems** lists. Pass a
`profiles` / `integrations` map only to flip specific rows to "Y".

## Step 4 — Generate

```
python3 .claude/scripts/docgen.py docs/generated/<id>-spec.json --outdir docs/generated
```

## Step 5 — Report

List the generated `.docx` paths and call out any fields you defaulted or left
blank so the user can fill them in before sharing. Do not commit or push the
generated files unless the user asks.

## Guardrails

- For a defect, **investigate the code and derive the RCA yourself** (Path A2) —
  never ask the user to supply the root cause, and never generate documents on an
  unconfirmed RCA.
- For a story, **derive the components-to-change from the pasted requirements by
  reading the code** (Path B2) — don't ask the user to list the components; ask
  clarifying questions instead, and confirm the change list before generating.
- Both root-cause claims (defect) and change-list claims (story) must be grounded
  in the actual code with `path:line` evidence, not guessed from the text alone.
- Always generate through `.claude/scripts/docgen.py`; never author `.docx` by hand.
- Never assume inputs — derive from git/code investigation or ask via `ask_user_tool`.
- Keep generated artifacts under `docs/generated/`.
- No authentication/login steps are needed; this flow only reads git/code and writes files.
