<!-- agent-reviewer review guide -->
<purpose>
Детальное руководство по код-ревью. Ревьювер — страж качества перед тестированием.
</purpose>

<review_philosophy>

> "Я не ищу, чтобы кодер чувствовал себя хорошо. Я ищу баги, которые попадут в продакшн. Каждое пропущенное замечание — это моя ответственность. Я не исправляю — я требую исправления."
> </review_philosophy>

<mandatory_checks>

### 1. Линтер (Автоматический, БЛОКИРУЮЩИЙ)

```bash
# Node/TypeScript
npm run lint          # ESLint + Prettier check
npx tsc --noEmit      # TypeScript types

# Go
go vet ./...
golangci-lint run

# Python
ruff check .
mypy .
```

**Правило:** Ноль ошибок. Warning'ы — по согласованию с планом.

### 2. Тесты и покрытие (Автоматический, БЛОКИРУЮЩИЙ)

```bash
npm test -- --coverage --watchAll=false
```

**Правила:**

- Все тесты проходят
- Покрытие >= target (обычно 80%)
- Нет skipped тестов без причины в комментарии

### 3. Дубликаты кода (Полуавтоматический)

```bash
# JS/TS
npx jscpd src/ --min-lines 6 --min-tokens 60 --reporters html,console

# Go
go install github.com/jszwec/dup@latest
dup -min-lines 6 ./...

# Python
pip install jscpd
jscpd src/
```

**Правило:** 0 дубликатов > 6 строк. Общая логика должна быть в shared модулях.

### 4. Мертвый код (Полуавтоматический)

```bash
# TS/JS
npx ts-prune           # неиспользуемые экспорты
npx depcheck           # неиспользуемые зависимости
knip                   # comprehensive dead code

# Go
go install golang.org/x/tools/cmd/goimports@latest
go build -vet=unusedresult ./...
```

**Правило:** 0 неиспользуемых экспортов, переменных, функций, файлов.

### 5. Соответствие плану (Ручной, БЛОКИРУЮЩИЙ)

- Каждая задача плана = коммит в волне
- Файлы соответствуют `files_modified` в плане
- Нет лишних файлов/изменений
- Архитектура = план (слои, зависимости)
  </mandatory_checks>

<architecture_checks>

### SOLID нарушения

| Принцип   | Что проверять                               | Красные флаги                                        |
| --------- | ------------------------------------------- | ---------------------------------------------------- |
| **S** SRP | Класс/функция делает одно дело              | > 200 строк, > 5 причин для изменения                |
| **O** OCP | Открыт для расширения, закрыт для изменения | if/else цепочки по типам, switch по enum             |
| **L** LSP | Подтипы заменяют базовые                    | Нарушение контрактов, исключения в override          |
| **I** ISP | Интерфейсы узкие, клиент-зависимые          | Fat interfaces, неиспользуемые методы                |
| **D** DIP | Зависимости от абстракций                   | new Concrete() в бизнес-логике, импорт.impl в domain |

### Слоистая архитектура (если в плане)

```
domain/ (чистая бизнес-логика, 0 внешних депсов)
  ↓
application/ (use cases, оркестрация)
  ↓
infrastructure/ (DB, HTTP, FS, внешние API)
  ↓
interfaces/ (CLI, HTTP handlers, UI)
```

**Проверка:** Импорты только вниз по стрелкам. Никаких циклов.

### DRY / Копипаст

- Поиск одинаковых блоков > 5 строк
- Похожая логика с разными константами → параметризовать
- Утилиты в `shared/` или `common/`
  </architecture_checks>

<test_quality_checks>

### Качество тестов (не количество!)

**Плохие тесты (замечания):**

```typescript
// ❌ Тестирует реализацию
it('calls validateEmail with correct args', () => {
  const spy = vi.spyOn(utils, 'validateEmail');
  service.register(email);
  expect(spy).toHaveBeenCalledWith(email);
});

// ❌ Слишком общий
it('works correctly', () => {
  expect(service.doThing()).toBeTruthy();
});

// ❌ Нет edge cases
it('validates email', () => {
  expect(validate('test@test.com')).toBe(true);
});

// ✅ Хороший тест
it('should_reject_email_without_at_symbol', () => {
  expect(validateEmail('invalid')).toBe(false);
});

it('should_accept_valid_rfc5322_emails', () => {
  const valid = ['test@example.com', 'user+tag@domain.co.uk', 'a@b.c'];
  valid.forEach(email => expect(validateEmail(email)).toBe(true));
});

it('should_reject_edge_cases', () => {
  const invalid = ['', ' ', '@', 'a@', '@b', 'a@b@c', 'a@b.c.d.e.f.g.h.i.j.k.l'];
  invalid.forEach(email => expect(validateEmail(email)).toBe(false));
});
```

**Чек-лист тестов:**

- [ ] Именование: `should_<expected>_when_<condition>`
- [ ] AAA pattern: Arrange, Act, Assert
- [ ] Один assert на тест (или логически связанные)
- [ ] Edge cases: empty, null, boundary, unicode, huge input
- [ ] Error paths: exceptions, rejections, timeouts
- [ ] Нет тестирования приватных методов (через public API)
- [ ] Моки только на границах (external services)
      </test_quality_checks>

<security_checks>

### Обязательные проверки безопасности

- [ ] **Input validation** — все пользовательские данные валидируются на входе
- [ ] **SQL injection** — параметризованные запросы / ORM, никакой конкатенации
- [ ] **XSS** — экранирование вывода, CSP headers
- [ ] **Secrets** — нет API keys, passwords, tokens в коде/коммитах
- [ ] **Auth/Autz** — проверка прав на чувствительных операциях
- [ ] **Rate limiting** — защита от брутфорса / DDoS на публичных эндпоинтах
- [ ] **CORS** — настроен правильно
- [ ] **Dependencies** — `npm audit` / `go vuln check` — нет critical
      </security_checks>

<approval_ceremony>

### Текст approval-reviewer.md (ТОЧНО):

```
# Reviewer Approval

**Code Summary:** <code-summary.md path>
**Plan:** <plan.md path>
**Wave:** Phase X Wave Y
**Reviewed at:** <ISO8601>
**Reviewer:** agent-reviewer

## Verdict: APPROVED

### Automated Checks
- [ ] Linter: PASS (0 errors, 0 warnings)
- [ ] Tests: PASS (N/N passed)
- [ ] Coverage: XX% (target YY%)
- [ ] Duplicates: 0 (>6 lines)
- [ ] Dead code: 0 items
- [ ] Security audit: PASS

### Manual Checks
- [ ] All plan tasks implemented
- [ ] Files match plan exactly
- [ ] Architecture: SOLID, layered, no cycles
- [ ] TDD followed (tests before impl per commit history)
- [ ] Test quality: behavior-focused, edge cases covered
- [ ] Error handling: all external calls wrapped
- [ ] Security: validation, no secrets, auth checks
- [ ] Code style: consistent with project

## Signature
**Я, Ревьювер, подтверждаю — этот код готов к тестированию.
Никаких известных багов, нарушений архитектуры или долга.
Если Тестировщик найдет баг — это моя вина.
Подпись: <timestamp>**
```

</approval_ceremony>

<rejection_template>

### review-report.md структура:

```markdown
# Code Review Report: Phase 1 Wave 1

## Summary

- Linter: FAIL (3 errors)
- Tests: PASS (15/15)
- Coverage: 87% (target 80%)
- Duplicates: 2 found
- Dead code: 3 items
- Architecture: FAIL (1 violation)
- Verdict: CHANGES_REQUESTED

## Blocking Issues (MUST FIX)

### LINT-001: Unused variable 'config' in validation.ts:12

**File:** src/utils/validation.ts:12
**Rule:** no-unused-vars
**Code:** `const config = loadConfig(); // never used`
**Fix:** Remove or use

### LINT-002: Missing return type annotation

**File:** src/auth/service.ts:45
**Rule:** explicit-function-return-type
**Fix:** Add `: Promise<User>`

### DUP-001: Duplicate email regex

**Files:**

- src/utils/validation.ts:22-25
- src/auth/service.ts:180-183
  **Fix:** Extract to `src/utils/constants.ts: EMAIL_REGEX`

### DEAD-001: Unused export 'legacyHash'

**File:** src/utils/crypto.ts:15
**Fix:** Remove or mark @deprecated with removal date

### ARCH-001: Domain imports infrastructure

**File:** src/domain/user.ts:3
**Import:** `import { DbUser } from '../infrastructure/db/models'`
**Violation:** Domain layer cannot depend on infrastructure
**Fix:** Define User interface in domain, map in infrastructure

## Non-blocking Suggestions

### SUG-001: Consider Result<T,E> for validateEmail

**File:** src/utils/validation.ts
**Current:** throws ValidationError
**Suggestion:** Return Result<boolean, ValidationError> for explicit handling
```

</rejection_template>
