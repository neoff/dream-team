<!-- agent-coder coding guide -->
<purpose>
Строгие правила TDD и реализации для Кодера. Никаких отклонений.
</purpose>

<tdd_rules>

### Жесткие правила TDD

1. **НИКАКОГО кода без падающего теста** — нулевая толерантность
2. **Тест пишется в файл тестов** — не в main код, не в консоль
3. **Тест должен быть конкретным** — конкретные входы, конкретные ожидания
4. **Один тест на одну задачу** (минимум), лучше — несколько (happy, edge, error)
5. **Коммит только после GREEN + REFACTOR** — не коммитить RED

### Цикл на задачу:

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

### Если тест не падает на шаге 3:

- Тест невалиден — проверяет не то, или всегда проходит
- Переписать тест до тех пор пока не упадет
- Частая ошибка: тест мокает то, что должен тестировать
  </tdd_rules>

<implementation_rules>

### Следование плану

- **План — закон**. Не менять архитектуру, не добавлять фичи, не упрощать "потому что проще"
- Если в плане ошибка — остановиться, обновить pipeline-state.json с `blocked_reason`, уведомить Менеджера
- Не принимать решений "на месте" — все решения в плане

### Качество кода

- **DRY** — выносить общую логику в утилиты (как в плане)
- **SOLID** — single responsibility, dependency inversion
- **Именование** — понятные имена, как в проекте (проверить существующий код)
- **Типизация** — строгая, нет `any` / `unknown` без нужды
- **Ошибки** — каждый внешний вызов: try/catch или Result<T,E>
- **Логирование** — структурированное, уровни debug/info/warn/error

### Коммиты

```
<type>(task-<id>): <краткое описание>

- Test: <что покрывает тест>
- Implements: Phase <X> Wave <Y> Task <Z>
- Plan-ref: <ссылка на задачу в plan.md>

Co-authored-by: agent-coder <pipeline@local>
```

Types: `feat` | `fix` | `refactor` | `test` | `docs` | `chore`

### Файловая структура

- Соответствовать плану точно
- Не создавать лишних файлов
- Не менять структуру без задачи в плане
  </implementation_rules>

<test_writing_guide>

### Unit тесты (основа)

```typescript
// Именование: should_<expected_behavior>_when_<condition>
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

### Integration тесты

- Реальные зависимости (БД, HTTP, FS) — через testcontainers / моки на границе
- Тестировать контракты, не реализацию
- Один интеграционный тест на ключевой user journey

### Покрытие

- Цель: 80%+ общий, 95%+ для бизнес-логики
- Исключения: main.ts, конфиги, типы — не считать
- `npm test -- --coverage` — проверять локально
  </test_writing_guide>

<common_traps>

1. **Писать реализацию, потом тест** — НАРУШЕНИЕ, перезапуск задачи
2. **Тест проходит сразу** — значит тест невалиден или функционал уже есть (проверить!)
3. **Коммитить без рефакторинга** — технический долг в пайплайне недопустим
4. **Игнорировать линтер** — `npm run lint` должен проходить перед коммитом
5. **Менять чужие тесты** — только свои, если не задача рефакторинга
6. **Хардкодить значения** — конфиг в env/константы
7. **Пропускать error handling** — каждый внешний вызов = потенциальная ошибка
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
