---
name: review-change
description: Review a change before it is handed over, committed or merged, the way the Claude Code team reviews its own code (claude.dev, "How the Claude Code team does code review", 2026-10-15). Runs the gates, has a fresh-context agent hunt for bugs against REVIEW.md, has separate verifiers vote on each finding, and reports only confirmed findings with file and line. Use after any change to games/*/src, kit/src or tools/, before every commit that touches a risky path, and whenever the owner asks for a review.
---

# Review a change

Writing code is cheap; knowing what could go wrong with it is the job. This skill moves most of
the reading to agents and leaves the owner the parts that need a person: the risky paths, the
evidence, and the decision.

## 1. Gates first

Run them from the repo root (commands in `docs/engineering/QA_AND_CI.md`): format, lint with 0
warnings, strict types, unit tests, build. Red stops the review: fix, then start again. A change
to a rule needs a spec that fails with the change reverted; break it on purpose and record how.

## 2. A fresh reviewer

Spawn one agent that has not seen the work. Give it only:

- the diff (`git diff` against the base) and the names of the changed files;
- `REVIEW.md`, whole;
- this instruction: find what could go wrong for a player. Every finding names a file and line
  and the input or sequence that breaks it, and is tagged Important, Nit (at most three) or
  Pre-existing. No style; the gates own style.

## 3. Verifiers vote

For each Important finding, spawn two agents that try to **disprove** it from the code: does
the breaking input really reach that line, or does something upstream stop it? Keep a finding
only when both fail to disprove it. If they split, keep it and mark it disputed. Run verifiers
in parallel.

## 4. At most two rounds

Fix the confirmed findings and review once more. After the second round, stop: list what is
left for the owner to fix, move to the backlog, or reject. A third round mostly re-finds old code.

## 5. Report to the owner

- The gate results, as run, with counts.
- Confirmed findings, most costly first, with file:line and the breaking sequence; disputed ones
  marked; rejected ones counted.
- **Risky paths touched** (`.github/CODEOWNERS`). For each, say that an agent's approval does not
  count there and offer to walk the owner through the changed lines with the `explain-code` skill.
  The owner is accountable for every change that ships, whoever typed it.
- How to revert, and whether a save schema changed.

Do not report a change as reviewed when a step was skipped; say which step and why.
