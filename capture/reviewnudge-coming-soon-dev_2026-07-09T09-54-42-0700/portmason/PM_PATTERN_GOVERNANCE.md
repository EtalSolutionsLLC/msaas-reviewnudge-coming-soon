# PM Pattern Governance

## Required decision path

1. Read the latest project snapshot.
2. Run `pm-capabilities search <need>`.
3. Run `pm-patterns search <need>`.
4. Reuse the existing capability when it satisfies the requirement.
5. When no pattern applies, classify the work as a candidate pattern before implementation.
6. Add the implementation boundary, tests, and enforcement.
7. Promote the candidate to canonical only after repeatable use validates it.

## Completion criteria

A reusable technical finding is not canonicalized until it has one or more concrete outcomes:

- registry entry;
- reusable Portmason capability;
- PM Lint rule;
- regression or contract test;
- narrow documented exception;
- TGF/EPC policy update.

Postmortem wording alone is evidence, not enforcement.

## Candidate pattern record

A candidate must define:

- problem and scope;
- nearest existing pattern and why it is insufficient;
- proposed ownership boundary;
- selectors, inputs, outputs, and replacement boundary;
- validation and rollback;
- whether the result belongs in Portmason, a project, or governance;
- promotion or rejection decision.

## Exceptions

Known-pattern deviations use `.pm-lint-exceptions` and must remain narrow, owned, dated, and reviewable. A recurring exception is evidence that the governing pattern or implementation needs revision.
