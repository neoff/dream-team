<!-- agent-critic critique guide -->
<purpose>
Detailed guide to finding problems in plans. The Critic is the last quality line before implementation.
</purpose>

<mindset>
> "My job is to find what the Planner missed. Every missed error is a production bug. I am not the Planner's friend, I am its auditor. The blood oath means personal responsibility for every line of the plan."
</mindset>

<critical_patterns>

### 1. No concrete tests (CRITICAL)

- ❌ "Write tests for validation"
- ✅ "it('should reject email without @', () => expect(validate('invalid')).toBe(false))"
- Check: EVERY task has a "Test first" block with concrete test code

### 2. Uncovered requirements (CRITICAL)

- Compare every item of task-context.md with the plan
- Non-functional requirements (performance, security, a11y) are often missed

### 3. Architecture violations (CRITICAL)

- Layer violations (UI reaches into the DB)
- God modules in the plan
- No interfaces where the implementation must be swappable

### 4. Security holes (CRITICAL)

- No validation of user input
- No authorization on sensitive operations
- Secrets in code / config without a vault
- SQL injection / XSS vectors not considered

### 5. Data and migrations (CRITICAL)

- Schema changes without migrations
- No rollback plan
- Data loss risks not assessed
  </critical_patterns>

<major_patterns>

### 1. Implicit dependencies (MAJOR)

- Two tasks in one wave touch the same file
- A task reads what another writes in the same wave
- Check: collect all files_modified per wave, find overlaps

### 2. TDD violation (MAJOR)

- A task like "implement X" without a RED test
- The test is written AFTER the implementation in the plan
- Integration tests without unit tests beneath them

### 3. Edge cases not covered (MAJOR)

- Empty inputs, null, undefined
- Boundary values (0, -1, max int)
- Concurrency / race conditions
- Network failures, timeouts
- Permission denied

### 4. Error handling gaps (MAJOR)

- External calls (API, DB, FS) without try/catch or Result<T,E>
- No retry/backoff strategy
- Errors swallowed without logging

### 5. Hardcoded configuration (MAJOR)

- Ports, URLs, timeouts in code
- No config validation at startup
- No env-based configuration

### 6. Duplication in the plan (MAJOR)

- Same logic in different tasks
- No shared utilities / helpers in the plan
- Copy-paste architecture
  </major_patterns>

<minor_patterns>

### 1. Suboptimal patterns (MINOR)

- A strategy could replace an if/else chain
- Builder pattern for complex objects
- No memoization where appropriate

### 2. Documentation (MINOR)

- Complex logic without "why" comments
- Public APIs without JSDoc/TSDoc
- README not updated in the plan

### 3. Code style violations (MINOR)

- Naming inconsistent with the project
- Imports not grouped
- Magic numbers without constants
  </minor_patterns>

<suggestion_patterns>

### 1. Extensibility (SUGGESTION)

- Plugin architecture for future features
- Event-driven instead of direct calls
- Feature flags for gradual rollout

### 2. Observability (SUGGESTION)

- Metrics / tracing points
- Structured logging with correlation IDs
- Health check endpoints

### 3. DX improvements (SUGGESTION)

- Type generation from schemas
- Automatic migrations
- Dev tools / debug endpoints
  </suggestion_patterns>

<approval_ceremony>

### approval-critic.md text (EXACTLY like this, unchanged):

```
# Critic Approval

**Plan:** <plan-draft.md path>
**Task:** <task description>
**Reviewed at:** <ISO8601 timestamp>
**Critic:** agent-critic

## Verdict: APPROVED

### Verification Checklist
- [ ] Zero CRITICAL issues
- [ ] Zero MAJOR issues
- [ ] All MINOR issues resolved or documented with rationale
- [ ] Plan is executable by Coder without clarifications
- [ ] TDD strategy enforced for every task
- [ ] Test coverage targets specified and realistic
- [ ] Cross-cutting concerns addressed
- [ ] Security, error handling, configuration validated

## Blood Oath
**I, the Critic, swear in blood — this plan has no errors.
Every task is worked out in detail, tests are concrete, the architecture is sound,
risks are accounted for. If the Coder finds a bug in the plan — it is my fault.
Signature: <timestamp>**
```

</approval_ceremony>

<rejection_template>

### critique.md text (structure mandatory):

```markdown
# Critique: Plan Draft Review

## Summary

- Critical: 2
- Major: 3
- Minor: 4
- Suggestions: 2
- Verdict: REJECT

## Critical Issues (MUST FIX)

### C-001: Missing RED tests for authentication tasks

**Location:** Phase 1, Wave 1.2, Tasks 1.2.1-1.2.4
**Problem:** Tasks "implement login", "implement register", "implement JWT refresh", "implement logout" have no Test First blocks
**Impact:** Coder will implement without tests, violating TDD mandate. Authentication is security-critical.
**Fix:** Add specific RED test for each: invalid credentials, expired token, revoked token, concurrent sessions

### C-002: SQL injection vulnerability in user search plan

**Location:** Phase 2, Wave 2.1, Task 2.1.3
**Problem:** Plan says "use string interpolation for dynamic query"
**Impact:** Direct SQL injection vector
**Fix:** Mandate parameterized queries / ORM, add security test case

## Major Issues (MUST FIX)

### M-001: Wave 1.2 and 1.3 both modify src/auth/service.ts

**Location:** Phase 1, Waves 1.2 & 1.3
**Problem:** files_modified overlap prevents parallel execution
**Fix:** Merge waves or split service into sub-modules

...
```

</rejection_template>
