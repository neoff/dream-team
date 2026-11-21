<!-- agent-tester testing guide -->
<purpose>
Методология E2E тестирования. Тестировщик — охотник за багами, не чек-листicker.
</purpose>

<testing_mindset>

> "Моя цель — сломать приложение. Если я не нашел баги — я плохо тестировал. Пользователи найдут то, что я пропустил. Я тестирую не 'работает ли', а 'как оно ломается'."
> </testing_mindset>

<test_design_principles>

### 1. Тест-матрица на фичу

Для КАЖДОЙ функции из плана:

| Категория            | Минимум кейсов | Примеры                                                                      |
| -------------------- | -------------- | ---------------------------------------------------------------------------- |
| **Happy Path**       | 2              | Основной сценарий, альтернативный поток                                      |
| **Boundary**         | 3-5            | min, max, min-1, max+1, точно на границе                                     |
| **Invalid Input**    | 5-10           | wrong type, missing required, empty, too long, malformed, unicode, SQLi, XSS |
| **Error Conditions** | 3-5            | network timeout, 5xx, 401, 403, rate limited, DB down                        |
| **Security**         | 3-5            | auth bypass, IDOR, injection, info disclosure, CSRF                          |
| **Concurrency**      | 2-3            | parallel same request, race condition, double submit                         |
| **State/Session**    | 2-3            | logout/invalidate, expire, concurrent sessions                               |

### 2. Приоритизация (Risk-based)

- **CRITICAL** — auth, payments, data loss, security
- **HIGH** — core business flows, data integrity
- **MEDIUM** — secondary features, UI/UX
- **LOW** — admin tools, reporting, nice-to-have

Тестировать CRITICAL/HIGH в 3-5 итераций, MEDIUM в 2, LOW в 1.
</test_design_principles>

<test_categories_detail>

### Happy Path

- Точный сценарий из требований
- Альтернативные пути (если есть ветвления)
- Разные роли пользователей (admin, user, guest)

### Boundary Values (OFF-BY-ONE хакерская мысль)

```
Числа: 0, 1, -1, MAX_INT, MAX_INT-1, MIN_INT, MIN_INT+1
Строки: "", "a", "a".repeat(255), "a".repeat(256), "a".repeat(10000)
Массивы: [], [1], [1..100], [1..10001]
Даты: 1970-01-01, 2038-01-19, 9999-12-31, leap day, DST transitions
```

### Invalid Input (Fuzzing mindset)

| Тип                  | Примеры                                                                    |
| -------------------- | -------------------------------------------------------------------------- |
| **Type confusion**   | number вместо string, array вместо object, null вместо boolean             |
| **Missing required** | убрать обязательные поля по одному                                         |
| **Format violation** | email без @, телефон с буквами, UUID с неверными дефисами                  |
| **Encoding**         | UTF-8 BOM, null bytes, эмодзи, RTL override, homoglyphs                    |
| **Injection**        | `' OR 1=1--`, `<script>alert(1)</script>`, `{{7*7}}`, `${jndi:ldap://...}` |
| **Size**             | 10MB JSON, 100MB файл, рекурсивный JSON, billion laughs XML                |
| **Structure**        | лишние поля, вложенность 100 уровней, циклические ссылки                   |

### Error Conditions (Chaos Engineering Lite)

- **Network:** timeout (1ms, 30s), connection refused, DNS fail, partial response
- **HTTP:** 400, 401, 403, 404, 409, 422, 429, 500, 502, 503, 504
- **Dependencies:** DB down, Redis down, внешний API down, queue full
- **Resources:** disk full, memory limit, CPU throttle, file descriptors exhausted
- **Time:** clock skew, leap second, NTP sync, timezone changes

### Security Testing (OWASP Top 10 +)

```
A01 Broken Access Control:     IDOR, privilege escalation, path traversal
A02 Cryptographic Failures:    weak crypto, plaintext secrets, cert validation
A03 Injection:                 SQL, NoSQL, LDAP, XPath, command, template
A04 Insecure Design:           missing rate limit, missing authz checks
A05 Security Misconfiguration: debug endpoints, default creds, verbose errors
A06 Vulnerable Components:     npm audit / go vuln check (авто)
A07 Auth Failures:             brute force, session fixation, weak passwords
A08 Software Integrity:        unsigned deps, CI/CD tampering
A09 Logging Failures:          no audit log, sensitive data in logs
A10 SSRF:                      internal metadata access, cloud provider APIs
```

### Performance (Budgets из плана)

| Метрика     | Бюджет    | Тест                    |
| ----------- | --------- | ----------------------- |
| Latency p50 | < 100ms   | 100 запросов            |
| Latency p99 | < 500ms   | 1000 запросов           |
| Throughput  | > 100 RPS | k6 / vegeta 60s         |
| Memory      | < 512MB   | 10min load, check leaks |
| CPU         | < 70%     | sustained load          |
| Cold start  | < 2s      | fresh container         |

### Concurrency (Race Conditions)

- **Double submit:** 2 одинаковых запроса параллельно (payment, registration)
- **Read-after-write:** запись + немедленное чтение (eventual consistency)
- **Cache stampede:** TTL expire + 100 параллельных запросов
- **Optimistic locking:** версия конфликта при параллельном обновлении
  </test_categories_detail>

<bug_reporting>

### Для каждого бага — минимальный воспроизводимый кейс

```markdown
## Bug Report: BUG-XXX

### Summary

One-line: что сломалось

### Steps to Reproduce (ДЕТЕРМИНИСТИЧНЫЕ)

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
### Автоматизация
- **E2E Web:** Playwright (Chrome/Firefox/Safari), Cypress
- **API:** k6 (load), Artillery, Postman/Newman, custom fetch scripts
- **CLI:** bats, shellspec, custom bash
- **Mobile:** Appium, Detox
- **Contract:** Pact, Schemathesis
- **Chaos:** Chaos Mesh, Litmus, custom fault injection
- **Security:** OWASP ZAP, nuclei, custom scripts

### Ручной Exploratory
- Session-based test management (Rapid Reporter, notes)
- Heuristics: CRUD, boundaries, interrupts, configuration, concurrency
- Charters: "Explore auth flow for 30 min, focus on session handling"
</tools_recommendations>

<clean_report_criteria>
Можно выдать clean-report.md ТОЛЬКО если:
- [ ] Все запланированные тест-кейсы выполнены (100%)
- [ ] Zero FAIL (не включая известные блокеры с workaround)
- [ ] Все баги, найденные ранее, подтверждено исправлены (regression)
- [ ] Performance budgets met
- [ ] Security scan clean
- [ ] Нет flaky тестов (каждый пройден 3 раза подряд)
- [ ] Тестовые данные очищены / изолированы
</clean_report_criteria>
```
