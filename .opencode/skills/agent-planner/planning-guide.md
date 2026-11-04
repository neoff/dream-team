<!-- agent-planner planning guide -->
<purpose>
Руководство по созданию детальных планов исполнения
</purpose>

<principles>
### 1. Атомарность задач
Каждая задача = один коммит = одна ответственность
- Не смешивать рефакторинг и новую функциональность
- Не смешивать несколько файлов без нужды
- Тест + реализация = одна задача

### 2. TDD-first мышление

Для КАЖДОЙ задачи:

1. **RED** — написать падающий тест (конкретный assert)
2. **GREEN** — минимальная реализация для прохождения теста
3. **REFACTOR** — улучшить код, тесты зеленые

План должен содержать конкретный тест для RED фазы.

### 3. Независимость волн

Задачи в одной волне НЕ должны трогать одни файлы.
Проверка: `files_modified` не пересекаются.

### 4. Явные зависимости

Если задача B зависит от задачи A — разные волны.
Зависимости документируются в плане.

### 5. Полнота детализации

Кодер не должен принимать архитектурных решений.
План отвечает на: что, где, как, какие паттерны, какие библиотеки, как тестировать.
</principles>

<plan_template>

````markdown
# Plan: <Название задачи>

## Metadata

- Task ID: <uuid>
- Created: <ISO8601>
- Planner: agent-planner
- Phases: <N>
- Total waves: <N>
- TDD: required
- Coverage target: 85%

## Phase 1: <Название фазы> (MVP / Core / Enhancement)

**Objective:** <Что достигается в этой фазе, 1-2 предложения>
**Waves:** <N>

### Wave 1.1: <Название волны>

**Objective:** <Что строится в этой волне>
**Parallel:** true/false
**Dependencies:** [] (IDs предыдущих волн)

#### Task 1.1.1: <Название задачи>

**Type:** implementation|test|refactor|config|docs
**Files to modify:**

- `src/module/file.ts` (new|modify)
- `tests/module/file.test.ts` (new)
  **Test first (RED):**

```typescript
// Конкретный тест, который должен упасть до реализации
it('should validate email format', () => {
  expect(validateEmail('invalid')).toBe(false);
  expect(validateEmail('test@example.com')).toBe(true);
});
```
````

**Implementation (GREEN):**

- Использовать regex pattern RFC 5322
- Функция `validateEmail(email: string): boolean` в `src/utils/validation.ts`
- Экспорт из `src/utils/index.ts`
  **Refactor:**
- Вынести regex в константу с комментарием
- Добавить JSDoc
  **Acceptance criteria:**
- [ ] Тест проходит
- [ ] Линтер чист
- [ ] Покрытие 100% для этой функции

#### Task 1.1.2: ...

```

### Phase 2: ...
```

## Cross-cutting concerns

### Error Handling

- Стратегия: Result<T, E> / exceptions / error codes
- Где логировать, где пробрасывать

### Logging

- Уровни: debug/info/warn/error
- Структурированный JSON логгер

### Configuration

- env-based, с валидацией на старте

### Security

- Input validation, sanitization
- Auth/autz boundaries

### Performance

- Бюджеты: latency < Xms, memory < YMB
- Профилирование точек

```
</plan_template>

<quality_checklist>
Перед передачей Критику проверить:
- [ ] Каждая задача имеет конкретный RED тест
- [ ] Нет задач типа "реализовать авторизацию" без деталей
- [ ] Волны не имеют пересечений по файлам
- [ ] Зависимости между волнами явны
- [ ] Покрытие тестами указано для каждой задачи
- [ ] Архитектурные решения обоснованы
- [ ] Cross-cutting concerns покрыты
- [ ] План исполняем Кодером БЕЗ уточнений
</quality_checklist>

<common_pitfalls>
1. **Слишком крупные задачи** — разбивать до атомарных
2. **Отсутствие конкретных тестов** — "написать тесты" недопустимо, нужен конкретный assert
3. **Неявные зависимости** — всегда объявлять files_modified
4. **Архитектурные решения "на ходу"** — все решать на этапе планирования
5. **Игнорирование ошибок** — каждый внешний вызов должен иметь обработку ошибок в плане
6. **Отсутствие конфигурации** — hardcoded значения = баг в плане
</common_pitfalls>
```
