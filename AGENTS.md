# AGENTS.md — Translation Reader (`my_translator_app`)

Инструкции для AI-агентов по этому репозиторию. Перед правками читай этот файл целиком.

Репозиторий пакета: `my_translator_app`. Продуктовое имя: **Translation Reader**.

Skills / OpenSpec / docs — в sibling meta: резолв [`project-map.md`](project-map.md) (`my_translator_meta` → `..`), затем `my_translator_meta/AGENTS.md` и `.agents/skills/` (`client/` = Flutter, `server/` = Rust core). Локальных `.agents/skills/` здесь нет.

Здесь **один репозиторий** с двумя связанными слоями:

| Слой | Роль | Каталог |
|------|------|---------|
| Flutter UI | экраны, жесты, отображение | `lib/` |
| Rust crate | ядро: парсинг, NLP, перевод, словарь, SQLite | `rust/` |
| FRB glue | FFI/WASM-сборка (не бизнес-логика) | `rust_builder/` |

Связка — **flutter_rust_bridge** (FRB) 2.13.0: API в Rust (`rust/src/api/`) → generated Dart (`lib/src/rust/`). На native — FFI, на Web — WASM (in-process). На текущем этапе внешние API-ключи не используются.

---

## What This Application Is

Мобильное и веб-приложение для **чтения субтитров и изучения языков через контекст**. Пользователь загружает файл субтитров, читает оригинал, тапает по незнакомым словам/фразам, получает перевод и сохраняет их в личный словарь. Сохранённые слова подсвечиваются при любом появлении, включая другие словоформы (подсветка по лемме).

Связка UI ↔ ядро — локальная, in-process FRB. Офлайн по умолчанию.

### Current vs target

В репозитории пока **scaffold-demo**: `lib/main.dart` вызывает `process_text` / `add_numbers` из Rust. Продуктовые сценарии ниже — целевой контракт; реализовывать по ним, не раздувая demo-логику на стороне Dart.

---

## What It Is Used For

### Основные сценарии (target)

1. **Чтение субтитров** — загрузка SRT / VTT / ASS(SSA); парсинг в Rust; построчное отображение в Flutter.
2. **Изучение слов по тапу** — тап по слову или выделение фразы → перевод, лемма, «добавить в словарь».
3. **Подсветка знакомых слов** — записи словаря подсвечиваются в тексте; матч по лемме (`run` / `running` / `ran` = одно слово).
4. **Разделённый экран** — сверху оригинал, снизу перевод; построчный синхронный скролл.
5. **Работа с ИИ** (опционально, позже) — перевод фраз, фразовые глаголы, контекст; разные провайдеры через API.
6. **Офлайн-перевод** — базовый перевод слов/фраз без интернета.

### Ключевые функции (target)

- Парсинг субтитров: SRT, VTT, ASS/SSA
- Токенизация + лемматизация (EN, RU и др.)
- Личный словарь: переводы + контекст
- Подсветка сохранённых слов с учётом морфологии
- Тап → карточка перевода + «добавить в словарь»
- Выделение фразы → перевод фразы целиком
- Split view: оригинал + перевод, sync scroll
- Опциональный ИИ для перевода/объяснений
- Локальное хранение (словарь, субтитры, настройки) — SQLite на устройстве
- Работа офлайн

### Сейчас в коде (scaffold)

- Flutter UI: поле ввода + кнопка «Вызвать Rust» + результат
- Rust: `process_text` → `to_uppercase`; `add_numbers`
- Платформы scaffold: Android, iOS, Linux, macOS, Windows, Web

---

## Who The Users Are

- Учащиеся языков: читают субтитры, копят словарь из контекста
- Пользователи Android / iOS / Web
- Разработчик / агент: правит Flutter UI и/или Rust API, затем FRB codegen

---

## Important

### Продуктовые принципы

- Вся тяжёлая логика — в **Rust**; Flutter только UI и оркестрация вызовов
- Офлайн по умолчанию; без обязательных внешних ключей на старте
- Быстрая итерация UI через Flutter Hot Reload; ядро — нативная производительность Rust
- Единая кодовая база для целевых платформ: **Android, iOS, Web (WASM)**

### Out of scope (сейчас)

- Синхронизация словаря между устройствами
- Облачные API перевода как обязательная часть
- Социальные функции
- Встроенный видеоплеер с синхронизацией субтитров
- Монетизация

### Технические правила репозитория

- **Источник правды для FFI API** — `rust/src/api/**/*.rs`. Не править вручную:
  - Dart: `lib/src/rust/**`
  - Rust: `rust/src/frb_generated.rs`
- После смены публичного API в `rust/src/api/` → FRB codegen → сборка/запуск Flutter
- `rust_builder/` — только glue/cargokit; бизнес-логику туда не класть
- `main()`: `await RustLib.init()` до `runApp`
- `integration_test/simple_test.dart` сейчас **рассинхронизирован** с UI в `main.dart` (ждёт старый `Result: Hello, Tom!`)

---

## Core Stack

| Слой | Технология |
|------|------------|
| UI | Flutter / Dart (`sdk: ^3.13.4`), `lib/` |
| Bridge | `flutter_rust_bridge` `2.13.0` (FFI native, WASM web) |
| Ядро | Rust edition `2021`, crate `rust_lib_my_translator_app` (`cdylib` + `staticlib`) |
| Хранение (target) | SQLite на устройстве через Rust (`diesel` / `rusqlite`) — ещё не подключено |
| Линты Dart | `flutter_lints` + `analysis_options.yaml` |

Path-зависимость: `pubspec.yaml` → `rust_lib_my_translator_app` (`rust_builder`) → crate `rust/`.

---

## UI And Components

### Target UX areas

- Загрузка / список субтитров
- Reader: построчный оригинал, тап/выделение, подсветка по лемме
- Карточка слова/фразы (перевод, лемма, «в словарь»)
- Split view: оригинал ↔ перевод, sync scroll
- Экран личного словаря
- Настройки (языки, опциональный ИИ — позже)

### Current scaffold

- `lib/main.dart` — `MyApp` → `MyHomePage` (demo TextField / кнопка / результат)
- Импорт API: `package:my_translator_app/src/rust/api/simple.dart`
- Роутера и state-management (Provider/Riverpod/Bloc) пока нет

---

## Data And Utilities

- Опциональный ИИ — только позже и явно.
- Все пользовательские данные — локально (target: SQLite из Rust).
- Конфиг FRB — `flutter_rust_bridge.yaml`:

  ```yaml
  rust_input: crate::api
  rust_root: rust/
  dart_output: lib/src/rust
  ```

- Пакет: `pubspec.yaml` (`name: my_translator_app`).

---

## Specific Tasks

| Задача | Где |
|--------|-----|
| Парсер SRT/VTT/ASS | Rust (`rust/src/…`), тонкий FFI в `api/` |
| Токенизация / лемматизация / матч словоформ | Rust |
| Словарь CRUD + контекст | Rust + SQLite |
| Офлайн-перевод слов/фраз | Rust |
| Подсветка / разметка токенов для UI | Rust готовит данные; Flutter рисует |
| Экраны reader / split / словарь / загрузка файла | `lib/` |
| Смена FFI-контракта | `rust/src/api/` → codegen → Dart-вызовы |

Не дублировать парсинг/лемматизацию/правила словаря на Dart.

---

## Development Tools

Команды запускает **агент** из корня репозитория. Не ждать подтверждения; падения чинить до завершения задачи.

| Действие | Команда |
|----------|---------|
| Зависимости Dart | `flutter pub get` |
| Анализ Dart | `flutter analyze` |
| Unit/widget tests | `flutter test` |
| Integration tests | `flutter test integration_test` |
| Запуск | `flutter run` / `flutter run -d chrome` |
| Сборка | `flutter build <platform>` (целевые: apk/ipa/web) |
| Rust check/test | `cargo check` / `cargo test` в `rust/` |
| FRB codegen | `flutter_rust_bridge_codegen generate` (CLI ≈ `2.13.0`) |

Package managers: pub (Dart), Cargo (`rust/`).

---

## How Boot / App Startup Is Organized

1. `main()` → `await RustLib.init()` (`#[frb(init)] init_app` на Rust).
2. `runApp(const MyApp())`.
3. UI вызывает generated API (`processText` / `addNumbers` в scaffold).

Rust:

1. `rust/src/lib.rs` — `api` + `frb_generated`
2. `rust/src/api/mod.rs` — модули API
3. `rust/src/api/simple.rs` — текущий demo API

По мере роста ядра ожидать модули вне `api/` (parse, lemma, dict, translate) и тонкий экспорт через `api/`.

---

## What Is Connected Globally

- `RustLib` после `RustLib.init()`
- Generated: `lib/src/rust/frb_generated.dart` (+ `.io` / `.web`)

Глобального DI / router guards пока нет.

---

## Combined Structure

```
my_translator_app/
├── AGENTS.md                 ← этот файл
├── flutter_rust_bridge.yaml
├── pubspec.yaml
├── lib/
│   ├── main.dart             ← UI (сейчас scaffold)
│   └── src/rust/             ← GENERATED (не править)
├── rust/
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── api/              ← публичный FFI API
│       └── frb_generated.rs  ← GENERATED
├── rust_builder/             ← glue / cargokit
├── integration_test/
├── test/
└── android|ios|linux|macos|windows|web/
```

Целевые платформы продукта: **Android, iOS, Web**. Остальные runner-каталоги — стандартный Flutter scaffold; не развивать как продукт без явной задачи.

---

## Layering / Dependency Direction

```
lib/**  (Flutter UI)
  → lib/src/rust/api/*  (generated)
      → rust/src/api/*  (FFI surface)
          → rust modules: parse / tokenize / lemmatize / dictionary / translate / db
```

- Flutter не хранит «истину» словаря и не парсит субтитры, если это уже в Rust.
- SQLite и файлы субтитров — через Rust (target).
- `rust_builder/` не трогать без нужды сборки.

---

## Flutter ↔ Rust Contract (current scaffold)

| Dart (generated) | Rust | Сейчас |
|------------------|------|--------|
| `processText(input:)` | `process_text` | `to_uppercase` |
| `addNumbers(a:, b:)` | `add_numbers` | `a + b` |
| `RustLib.init()` | `init_app` | `setup_default_user_utils()` |

### Ожидаемые области API (target, ещё нет)

- parse subtitles → структура строк/таймкодов
- tokenize / lemmatize → токены + леммы для подсветки и тапа
- dictionary add/list/remove + lookup by lemma
- translate word/phrase (offline)
- (позже) optional AI explain/translate

Менять контракт только через Rust `api/` + codegen + обновление UI и тестов.

---

## Business Entities And Areas (target)

- **Subtitle document** — файл + распарсенные cues (текст, таймкоды)
- **Token / Lemma** — единица тапа и ключ подсветки/словаря
- **Dictionary entry** — лемма, перевод(ы), контекст (фраза/строка субтитров)
- **Reader session** — открытый документ, позиция скролла, режим split
- **Settings** — языки, (позже) ИИ-провайдер

Размещение: сущности и правила — Rust; виджеты и жесты — Flutter.

---

## Tests

- `integration_test/simple_test.dart` — устарел относительно текущего UI
- Rust unit-тесты — рядом с парсером/леммой/словарём (`cargo test` в `rust/`)
- Dart widget/unit — `test/` + `flutter test`

При смене FFI или reader UX — обновлять тесты в том же изменении.

---

## OpenSpec / Skills

Локальных `.agents/skills/` в этом репо нет. Канон для агента:

1. Этот `AGENTS.md` + код `lib/` и `rust/`.
2. Meta sibling: `my_translator_meta` — резолв через [`project-map.md`](project-map.md) (ключ `my_translator_meta` → `..`).
3. Карта путей / OpenSpec / индекс skills: `my_translator_meta/docs/projects-map.md`, `my_translator_meta/AGENTS.md`, `my_translator_meta/.agents/AGENTS.md`.
4. Skills: `my_translator_meta/.agents/skills/client/` (Flutter), `…/server/` (Rust), `…/skills/` (OpenSpec / оркестраторы).

---

## Git / Workflow Notes

- Не коммитить секреты; `rust/target/`, `build/`, `.dart_tool/` — вне коммита
- Не пушить и не создавать PR без явной просьбы
- При старте задачи с уже грязной рабочей копией — спросить, что делать с локальными изменениями

---

## Related Layers (in-repo)

- **Flutter** (`lib/`) — UI Translation Reader
- **Rust** (`rust/`) — авторитетное ядро (parse / NLP / dict / offline translate / SQLite)
- Согласование контракта — только через FRB codegen, не ручным edit generated-файлов
