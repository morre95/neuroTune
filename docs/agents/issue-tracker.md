# Issue tracker: GitHub

Specs and tickets live in GitHub Issues for `morre95/neuroTune`.
Use the `gh` CLI. Target this repository explicitly with
`--repo morre95/neuroTune`.

## Conventions

- Create an issue with `gh issue create --title "..." --body-file <file>`.
- Read an issue with `gh issue view <number>
  --json number,title,body,labels,comments`.
- List issues with `gh issue list --state open
  --json number,title,body,labels,assignees`.
- Edit bodies and write comments using `--body-file` for multiline text.
- Apply or remove labels with `gh issue edit`.
- Close completed work with `gh issue close <number>`. Record the
  implementation, validation results, and commit or PR link first.
- Do not close the parent spec until its entire scope is complete.

When a skill says “publish to the issue tracker,” create a GitHub issue.
When it says “fetch the relevant ticket,” read that issue.

## Parent specs and dependencies

Publish one parent spec and one child issue per implementation ticket.
Create children with `gh issue create --parent <spec-number>`.
For existing issues, use `gh issue edit <parent> --add-sub-issue <child>`.

Use native blocking relationships:
`gh issue edit <child> --add-blocked-by <blocker>`.

If these relationships are unavailable, put `Part of #<parent>` and
`Blocked by: #<blocker>, ...` at the top of each child body and maintain
a task list in the parent.

The implementation frontier consists of open, unclaimed tickets whose
blockers are all resolved. Claim work with
`gh issue edit <number> --add-assignee @me`.
Resolve tickets only after implementation and relevant validation.

## Pull requests as a triage surface

PRs as a request surface: no.

## Wayfinding

A wayfinder map is a parent issue labelled `wayfinder:map`.
Its children use `wayfinder:<type>` labels for research, prototype,
grilling, or task work. Use the same parent and blocking conventions.

When resolving a child, add its answer and append a brief context
pointer to the map’s Decisions-so-far section.
