# Domain docs

This repository uses a single-context layout:
root `GLOSSARY.md` and `docs/adr/`.

## Before exploring

Read `GLOSSARY.md` and ADRs relevant to the work.
If `GLOSSARY-MAP.md` is introduced later, follow its pointers to the
relevant context glossaries and ADRs.

If these documents do not exist, proceed silently. Do not suggest
creating them upfront. Domain-modeling work creates them when terms
or decisions are actually resolved.

## Vocabulary

Use the glossary’s established terms in specs, issues, code,
hypotheses, and tests. Avoid synonyms it explicitly excludes.
If a concept is missing, reconsider the terminology or note the gap
for domain-modeling work.

## Decisions

Surface conflicts with existing ADRs explicitly, identifying the
ADR and explaining why the decision should be reconsidered.
