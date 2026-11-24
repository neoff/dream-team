<!-- agent-tester testing guide -->
<purpose>
E2E testing methodology. The Tester is a bug hunter, not a checklist ticker.
</purpose>

<testing_mindset>

> "My goal is to break the application. If I found no bugs — I tested badly. Users will find what I missed. I test not 'does it work' but 'how does it break'."
> </testing_mindset>

<test_design_principles>

### 1. Per-feature test matrix

For EACH function from the plan:

| Category             | Min cases      | Examples                                                                     |
| -------------------- | -------------- | ---------------------------------------------------------------------------- |
| **Happy Path**       | 2              | Main scenario, alternative flow                                              |
| **Boundary**         | 3-5            | min, max, min-1, max+1, exactly on the boundary                              |
| **Invalid Input**    | 5-10           | wrong type, missing required, empty, too long, malformed, unicode, SQLi, XSS |
| **Error Conditions** | 3-5            | network timeout, 5xx, 401, 403, rate limited, DB down                        |
| **Security**         | 3-5            | auth bypass, IDOR, injection, info disclosure, CSRF                          |
| **Concurrency**      | 2-3            | parallel same request, race condition, double submit                         |
| **State/Session**    | 2-3            | logout/invalidate, expire, concurrent sessions                               |

### 2. Prioritization (Risk-based)

- **CRITICAL** — auth, payments, data loss, security
- **HIGH** — core business flows, data integrity
- **MEDIUM** — secondary features, UI/UX
- **LOW** — admin tools, reporting, nice-to-have

Test CRITICAL/HIGH in 3-5 iterations, MEDIUM in 2, LOW in 1.
</test_design_principles>

<test_categories_detail>

### Happy Path

- The exact scenario from the requirements
- Alternative paths (if there are branches)
- Different user roles (admin, user, guest)

### Boundary Values (OFF-BY-ONE hacker mindset)

```
Numbers: 0, 1, -1, MAX_INT, MAX_INT-1, MIN_INT, MIN_INT+1
Strings: "", "a", "a".repeat(255), "a".repeat(256), "a".repeat(10000)
Arrays: [], [1], [1..100], [1..10001]
Dates: 1970-01-01, 2038-01-19, 9999-12-31, leap day, DST transitions
```

### Invalid Input (Fuzzing mindset)

| Type                 | Examples                                                                   |
| -------------------- | -------------------------------------------------------------------------- |
| **Type confusion**   | number instead of string, array instead of object, null instead of boolean |
| **Missing required** | remove required fields one by one                                          |
| **Format violation** | email without @, phone with letters, UUID with wrong dashes                |
| **Encoding**         | UTF-8 BOM, null bytes, emoji, RTL override, homoglyphs                     |
| **Injection**        | `' OR 1=1--`, `<script>alert(1)</script>`, `{{7*7}}`, `${jndi:ldap://...}` |
| **Size**             | 10MB JSON, 100MB file, recursive JSON, billion laughs XML                  |
| **Structure**        | extra fields, 100 levels of nesting, circular references                   |

### Error Conditions (Chaos Engineering Lite)

- **Network:** timeout (1ms, 30s), connection refused, DNS fail, partial response
- **HTTP:** 400, 401, 403, 404, 409, 422, 429, 500, 502, 503, 504
- **Dependencies:** DB down, Redis down, external API down, queue full
- **Resources:** disk full, memory limit, CPU throttle, file descriptors exhausted
- **Time:** clock skew, leap second, NTP sync, timezone changes

### Security Testing (OWASP Top 10 +)

```
A01 Broken Access Control:     IDOR, privilege escalation, path traversal
A02 Cryptographic Failures:    weak crypto, plaintext secrets, cert validation
A03 Injection:                 SQL, NoSQL, LDAP, XPath, command, template
A04 Insecure Design:           missing rate limit, missing authz checks
A05 Security Misconfiguration: debug endpoints, default creds, verbose errors
A06 Vulnerable Components:     npm audit / go vuln check (automated)
A07 Auth Failures:             brute force, session fixation, weak passwords
A08 Software Integrity:        unsigned deps, CI/CD tampering
A09 Logging Failures:          no audit log, sensitive data in logs
A10 SSRF:                      internal metadata access, cloud provider APIs
```

### Performance (Budgets from the plan)

| Metric      | Budget    | Test                    |
| ----------- | --------- | ----------------------- |
| Latency p50 | < 100ms   | 100 requests            |
| Latency p99 | < 500ms   | 1000 requests           |
| Throughput  | > 100 RPS | k6 / vegeta 60s         |
| Memory      | < 512MB   | 10min load, check leaks |
| CPU         | < 70%     | sustained load          |
| Cold start  | < 2s      | fresh container         |

### Concurrency (Race Conditions)

- **Double submit:** 2 identical requests in parallel (payment, registration)
- **Read-after-write:** write + immediate read (eventual consistency)
- **Cache stampede:** TTL expire + 100 parallel requests
- **Optimistic locking:** version conflict on parallel update
  </test_categories_detail>

<bug_reporting>

### For each bug — a minimal reproducible case

```markdown
## Bug Report: BUG-XXX

### Summary

One-line: what broke

### Steps to Reproduce (DETERMINISTIC)

1. Start app with config X
2. Login as user A
3. POST /api/resource { "field": "value" }
4. Observe response

### Expected

HTTP 201, resource created, location header

### Actual

HTTP 500, stack trace in logs, no resource created

### Reproducibility

100% (5/5 runs)

### Environment

- OS: macOS 15.0
- App version: commit abc123
- Config: .env.test
- Dependencies: PostgreSQL 16, Redis 7

### Logs/Traces
```

<relevant logs>
```

### Severity

CRITICAL / HIGH / MEDIUM / LOW

### Workaround

None / description

```
</bug_reporting>

<tools_recommendations>
### Automation
- **E2E Web:** Playwright (Chrome/Firefox/Safari), Cypress
- **API:** k6 (load), Artillery, Postman/Newman, custom fetch scripts
- **CLI:** bats, shellspec, custom bash
- **Mobile:** Appium, Detox
- **Contract:** Pact, Schemathesis
- **Chaos:** Chaos Mesh, Litmus, custom fault injection
- **Security:** OWASP ZAP, nuclei, custom scripts

### Manual Exploratory
- Session-based test management (Rapid Reporter, notes)
- Heuristics: CRUD, boundaries, interrupts, configuration, concurrency
- Charters: "Explore auth flow for 30 min, focus on session handling"
</tools_recommendations>

<clean_report_criteria>
You may produce clean-report.md ONLY if:
- [ ] All planned test cases were executed (100%)
- [ ] Zero FAIL (excluding known blockers with a workaround)
- [ ] All previously found bugs are confirmed fixed (regression)
- [ ] Performance budgets met
- [ ] Security scan clean
- [ ] No flaky tests (each passed 3 times in a row)
- [ ] Test data cleaned up / isolated
</clean_report_criteria>
```
