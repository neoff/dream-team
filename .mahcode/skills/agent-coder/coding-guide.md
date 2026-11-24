<!-- agent-coder coding guide -->
<purpose>
Strict TDD and implementation rules for the Coder. No deviations.
</purpose>

<tdd_rules>

### Hard TDD rules

1. **NO code without a failing test** — zero tolerance
2. **The test is written in a test file** — not in main code, not in the console
3. **The test must be concrete** — concrete inputs, concrete expectations
4. **One test per task** (minimum), better — several (happy, edge, error)
5. **Commit only after GREEN + REFACTOR** — do not commit RED

### Per-task cycle:

```
┌─────────────────────────────────────┐
│ 1. READ plan: Test First block      │
│ 2. WRITE test file                  │
│ 3. RUN test → MUST FAIL (RED)       │
│ 4. WRITE minimal implementation     │
│ 5. RUN test → MUST PASS (GREEN)     │
│ 6. REFACTOR (clean code, DRY, SOLID)│
│ 7. RUN all tests → ALL GREEN        │
│ 8. COMMIT (atomic, message format)  │
│ 9. UPDATE code-summary.md           │
└─────────────────────────────────────┘
```

### If the test does not fail at step 3:

- The test is invalid — it checks the wrong thing or always passes
- Rewrite the test until it fails
- Common mistake: the test mocks what it is supposed to test
  </tdd_rules>

<implementation_rules>

### Following the plan

- **The plan is law**. Do not change the architecture, add features, or simplify "because it's easier"
- If the plan has an error — stop, update pipeline-state.json with `blocked_reason`, notify the Manager
- Make no decisions "on the spot" — all decisions are in the plan

### Code quality

- **DRY** — move shared logic into utilities (as in the plan)
- **SOLID** — single responsibility, dependency inversion
- **Naming** — clear names, consistent with the project (check existing code)
- **Typing** — strict, no `any` / `unknown` without need
- **Errors** — every external call: try/catch or Result<T,E>
- **Logging** — structured, levels debug/info/warn/error

### Commits

```
<type>(task-<id>): <short description>

- Test: <what the test covers>
- Implements: Phase <X> Wave <Y> Task <Z>
- Plan-ref: <reference to the task in plan.md>

Co-authored-by: agent-coder <pipeline@local>
```

Types: `feat` | `fix` | `refactor` | `test` | `docs` | `chore`

### File structure

- Match the plan exactly
- Do not create extra files
- Do not change the structure without a task in the plan
  </implementation_rules>

<test_writing_guide>

### Unit tests (foundation)

```typescript
// Naming: should_<expected_behavior>_when_<condition>
it('should_return_false_when_email_invalid', () => {
  // Arrange
  const input = 'not-an-email';

  // Act
  const result = validateEmail(input);

  // Assert
  expect(result).toBe(false);
});

it('should_return_true_when_email_valid', () => {
  expect(validateEmail('test@example.com')).toBe(true);
  expect(validateEmail('user+tag@domain.co.uk')).toBe(true);
});

// Edge cases
it('should_return_false_when_empty_string', () => {
  expect(validateEmail('')).toBe(false);
});

it('should_return_false_when_null', () => {
  expect(validateEmail(null as any)).toBe(false);
});

// Error cases
it('should_throw_when_disposal_not_supported', () => {
  expect(() => validator.dispose()).toThrow('Not supported');
});
```

### Integration tests

- Real dependencies (DB, HTTP, FS) — via testcontainers / mocks at the boundary
- Test contracts, not implementation
- One integration test per key user journey

### Coverage

- Target: 80%+ overall, 95%+ for business logic
- Exclusions: main.ts, configs, types — not counted
- `npm test -- --coverage` — check locally
  </test_writing_guide>

<common_traps>

1. **Writing the implementation, then the test** — VIOLATION, restart the task
2. **The test passes immediately** — the test is invalid or the functionality already exists (check!)
3. **Committing without refactoring** — technical debt in the pipeline is unacceptable
4. **Ignoring the linter** — `npm run lint` must pass before the commit
5. **Changing others' tests** — only your own, unless it is a refactoring task
6. **Hardcoding values** — config goes to env/constants
7. **Skipping error handling** — every external call = a potential error
   </common_traps>

<code_summary_template>

```markdown
# Code Summary: Phase 1 Wave 1

## Wave Objective

Build email validation module with RFC 5322 compliance

## Completed Tasks

| Task                           | Commit  | Tests    | Status |
| ------------------------------ | ------- | -------- | ------ |
| 1.1.1: validateEmail function  | a1b2c3d | 5 passed | ✅     |
| 1.1.2: ValidationError class   | e4f5g6h | 3 passed | ✅     |
| 1.1.3: Export from utils/index | i7j8k9l | 1 passed | ✅     |

## Test Results
```

Test Suites: 3 passed, 3 total
Tests: 9 passed, 9 total
Coverage: 94.2% (statements), 91.7% (branches)

```

## Files Modified
- `src/utils/validation.ts` (new)
- `src/utils/errors.ts` (new)
- `src/utils/index.ts` (modified)
- `tests/utils/validation.test.ts` (new)
- `tests/utils/errors.test.ts` (new)

## Deviations from Plan
- None

## Ready for Review: true
```

</code_summary_template>
