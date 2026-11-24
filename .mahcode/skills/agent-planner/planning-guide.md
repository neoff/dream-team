<!-- agent-planner planning guide -->
<purpose>
Guide to creating detailed execution plans
</purpose>

<principles>
### 1. Task atomicity
Each task = one commit = one responsibility
- Do not mix refactoring and new functionality
- Do not mix several files without need
- Test + implementation = one task

### 2. TDD-first thinking

For EACH task:

1. **RED** — write a failing test (a concrete assert)
2. **GREEN** — minimal implementation to pass the test
3. **REFACTOR** — improve the code, tests stay green

The plan must contain a concrete test for the RED phase.

### 3. Wave independence

Tasks in one wave must NOT touch the same files.
Check: `files_modified` do not overlap.

### 4. Explicit dependencies

If task B depends on task A — different waves.
Dependencies are documented in the plan.

### 5. Complete detail

The Coder must not make architecture decisions.
The plan answers: what, where, how, which patterns, which libraries, how to test.
</principles>

<plan_template>

````markdown
# Plan: <Task name>

## Metadata

- Task ID: <uuid>
- Created: <ISO8601>
- Planner: agent-planner
- Phases: <N>
- Total waves: <N>
- TDD: required
- Coverage target: 85%

## Phase 1: <Phase name> (MVP / Core / Enhancement)

**Objective:** <What this phase achieves, 1-2 sentences>
**Waves:** <N>

### Wave 1.1: <Wave name>

**Objective:** <What this wave builds>
**Parallel:** true/false
**Dependencies:** [] (IDs of previous waves)

#### Task 1.1.1: <Task name>

**Type:** implementation|test|refactor|config|docs
**Files to modify:**

- `src/module/file.ts` (new|modify)
- `tests/module/file.test.ts` (new)
  **Test first (RED):**

```typescript
// A concrete test that must fail before implementation
it('should validate email format', () => {
  expect(validateEmail('invalid')).toBe(false);
  expect(validateEmail('test@example.com')).toBe(true);
});
```
````

**Implementation (GREEN):**

- Use the RFC 5322 regex pattern
- Function `validateEmail(email: string): boolean` in `src/utils/validation.ts`
- Export from `src/utils/index.ts`
  **Refactor:**
- Move the regex into a commented constant
- Add JSDoc
  **Acceptance criteria:**
- [ ] Test passes
- [ ] Linter clean
- [ ] 100% coverage for this function

#### Task 1.1.2: ...

```

### Phase 2: ...
```

## Cross-cutting concerns

### Error Handling

- Strategy: Result<T, E> / exceptions / error codes
- Where to log, where to propagate

### Logging

- Levels: debug/info/warn/error
- Structured JSON logger

### Configuration

- env-based, validated at startup

### Security

- Input validation, sanitization
- Auth/authz boundaries

### Performance

- Budgets: latency < Xms, memory < YMB
- Profiling points

```
</plan_template>

<quality_checklist>
Before passing to the Critic check:
- [ ] Every task has a concrete RED test
- [ ] No tasks like "implement authorization" without details
- [ ] Waves have no file overlaps
- [ ] Dependencies between waves are explicit
- [ ] Test coverage is stated for every task
- [ ] Architecture decisions are justified
- [ ] Cross-cutting concerns are covered
- [ ] The plan is executable by the Coder WITHOUT clarifications
</quality_checklist>

<common_pitfalls>
1. **Tasks too large** — split down to atomic ones
2. **No concrete tests** — "write tests" is unacceptable, a concrete assert is required
3. **Implicit dependencies** — always declare files_modified
4. **Architecture decisions "on the fly"** — decide everything at the planning stage
5. **Ignoring errors** — every external call must have error handling in the plan
6. **No configuration** — hardcoded values = a bug in the plan
</common_pitfalls>
```
