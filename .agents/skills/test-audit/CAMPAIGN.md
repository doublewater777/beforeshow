# Test-pruning campaign

Campaign mode prunes one whole BeforeShow subsystem's test surface in one PR.
The value bar, retention bar, candidate evidence, and validation rules in
[SKILL.md](SKILL.md) apply to every lane. Use campaign mode only when a focused
audit is too narrow; optimize for preserved confidence, not deletion count.

## 1. Baseline

Pin the current `main` SHA. Record the subsystem's test/support line counts and
the baseline pass/fail state of every in-scope test file. A baseline failure is
potentially a product bug; do not classify it as stale merely because the audit
found it.

Done when every in-scope test file has a recorded baseline result.

## 2. Lanes and inventory

Split by production owner boundaries, not filename prefixes. Typical BeforeShow
lanes include App/root routing, CurrentShow, Listening, AddShow, Footprints,
Memory, Infrastructure, Shared/Widget, and test/tooling contracts. Include
cross-feature cases at the owner that actually defines the contract.

Done when every in-scope test declaration belongs to exactly one lane.

## 3. Read-only ledger per lane

Read every assigned test in full, including parameter tables. Also read its
production owner, entry point, callers, callees, sibling implementations,
relevant history, and CI routing. Mark each test declaration:

- `R`: retain; name the contract and credible regression it catches.
- `F`: retain the contract but fix a vacuous or misleading assertion.
- `C`: consolidate into a stronger owner-boundary suite; name the keeper first.
- `D`: delete; name the stronger remaining proof or why no contract exists.

Judge assertions rather than test names. Source inspection is not automatically
junk when the source itself is the independent architecture/release contract.

Done when every declaration has a mark and an evidence line.

## 4. Layer plan per lane

Treat the ledger as evidence, not a deletion list. Look for redundant layers:
for example, a source-string test around behavior already exercised by a policy
or coordinator suite, or an XCTest that duplicates the dedicated architecture
checker. Name one keeper for each contract and prefer the strongest executable
boundary.

Done when each lane plan names retired assertions/files, keepers, any assertions
that must move, and any test-only production seams that become removable.

## 5. Cutover

Edit one owner-boundary batch at a time. Remove test-only production seams only
when the audited tests are their last legitimate callers. Do not add replacement
tests that merely restate the same implementation shape.

If project structure changes, update `apps/ios/project.yml`, run
`xcodegen generate`, and commit the generated Xcode project. Do not edit only
the pbxproj.

Done when the lane plan is applied and its keeper tests pass.

## 6. Preservation review

Before completion, have an independent reviewer compare deleted coverage with
the keepers and look for contracts that lost their only proof. For restored
contracts, deliberately mutate the production owner when practical and confirm
the keeper fails for the intended reason, then restore the source exactly.

Done when each reported gap is restored or rejected with source evidence.

## 7. Product defects

A retained baseline failure is a bug report. Repair it at its owner in a
separate commit and prove the fix through the real boundary. Keep unrelated
product defects as named follow-ups rather than expanding the audit PR.

Done when every repaired defect has failing-before / passing-after evidence.

## 8. Validation and handoff

Follow root `AGENTS.md`:

- run `python3 apps/ios/scripts/check_architecture.py` for architecture changes;
- run focused signed XCTest selections on the iPhone 17 simulator with
  `DEVELOPMENT_TEAM=29C8MS76CZ`;
- run the repository PR verifier for the exact current HEAD;
- report production/tooling LOC separately from tests/test support;
- hand the exact current HEAD to `pr-reviewer` before merge.

Campaigns can outlive changes on `main`. Reconcile deliberately and confirm any
new regression coverage from `main` still has a keeper. Never merge without
explicit user authorization.

## Provenance

Adapted from openclaw/openclaw `.agents/skills/test-audit/CAMPAIGN.md` for
BeforeShow's Swift/XCTest/XcodeGen architecture and verification flow.
