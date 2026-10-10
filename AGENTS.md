# AGENTS.md — Translation Reader (`my_translator_app`)

Инструкции для AI-агентов по этому репозиторию. Перед правками читай этот файл целиком.

Репозиторий пакета: `my_translator_app`. Продуктовое имя: **Translation Reader**.

Skills / OpenSpec / docs — в sibling meta: резолв [`project-map.md`](project-map.md) (`my_translator_meta` → `..`), затем `my_translator_meta/AGENTS.md` и `.agents/skills/` (`client/` = Flutter, `server/` = Rust core). Локальных `.agents/skills/` здесь нет.

Здесь **один репозиторий** с двумя связанными слоями:

| Слой | Роль | Каталог |
|------|------|---------|
| Flutter UI | экраны, жесты, отображение, **user persistence (Drift)** | `lib/` |
| Rust crate | compute: парсинг, NLP, офлайн-перевод (без user SQLite) | `rust/` |
| FRB glue | FFI/WASM-сборка (не бизнес-логика) | `rust_builder/` |

Связка — **flutter_rust_bridge** (FRB) 2.13.0: API в Rust (`rust/src/api/`) → generated Dart (`lib/src/rust/`). На native — FFI, на Web — WASM (in-process). На текущем этапе внешние API-ключи не используются.

---

## What This Application Is

Мобильное и веб-приложение для **чтения субтитров и изучения языков через контекст**. Пользователь загружает файл субтитров, читает оригинал, тапает по незнакомым словам/фразам, получает перевод и сохраняет их в личный словарь. Сохранённые слова подсвечиваются при любом появлении, включая другие словоформы (подсветка по лемме).

Связка UI ↔ ядро — локальная, in-process FRB. Офлайн по умолчанию.

### Current vs target

**Сейчас:** product shell Library + Vocabulary; user data в **Drift** (`lib/data/`). Library open → `loadBytes` → FRB `parseSubtitles` → cues-first **Reader** (`lib/features/reader/`). Rust: `rust/src/parse/` + `api/parse.rs` (плюс scaffold `process_text` / `add_numbers`, не home UI).

**Ещё target:** tokenize / lemma highlight / word card / split / offline translate — следующие changes.

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
- Локальное хранение (папки/документы библиотеки, словарь, настройки later) — **Drift** в Flutter (`lib/`)
- Работа офлайн

### Сейчас в коде

- Flutter: shell **Library** (папки / import / open→Reader) + **Vocab** (CRUD); cues-first Reader; Drift schema + repositories (`loadBytes` / content store `load`)
- Rust: `parse/` + FRB `parse_subtitles`; scaffold `process_text` / `add_numbers` / `init_app` ещё в crate
- Платформы: Android, iOS, Web (+ desktop runners из Flutter scaffold)

---

## Who The Users Are

- Учащиеся языков: читают субтитры, копят словарь из контекста
- Пользователи Android / iOS / Web
- Разработчик / агент: правит Flutter UI и/или Rust API, затем FRB codegen

---

## Important

### Продуктовые принципы

- Тяжёлый **compute** (parse / tokenize / lemmatize / offline translate) — в **Rust**; Flutter — UI, оркестрация FRB и **user persistence через Drift**
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
| Ядро (compute) | Rust edition `2021`, crate `rust_lib_my_translator_app` (`cdylib` + `staticlib`) |
| Хранение (user data) | **Drift** в Flutter `lib/` (folders / documents / dictionary; Android / iOS / Web) |
| Линты Dart | `flutter_lints` + `analysis_options.yaml` |

Rust **не** владеет пользовательским SQLite (`rusqlite` / `diesel` / `rust/src/db` для user data — не канон).

Path-зависимость: `pubspec.yaml` → `rust_lib_my_translator_app` (`rust_builder`) → crate `rust/`.

---

## UI And Components

### UX areas

**Сейчас:** Library (папки / import / open), cues-first Reader (таймкоды + текст), Vocab CRUD.

**Target (later):** тап/выделение + подсветка по лемме, карточка слова/фразы, split view, настройки (языки, опциональный ИИ).

Роутера и state-management пакетов (Provider/Riverpod/Bloc) пока нет — `Navigator` + screen state.

---

## Data And Utilities

- Опциональный ИИ — только позже и явно.
- Все пользовательские данные — локально через **Drift** в `lib/` (библиотека папок/документов, личный словарь; settings later). Source of truth — Drift, не Rust SQLite.
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
| Библиотека папок / документов (`library/folders`, `library/documents`) | Drift в `lib/` |
| Словарь CRUD + контекст (`dictionary/entries`) | Drift в `lib/` (persist); NLP lemma keys — Rust when compute lands |
| Офлайн-перевод слов/фраз | Rust |
| Подсветка / разметка токенов для UI | Rust готовит данные; Flutter рисует |
| Экраны library / vocab / reader / split | `lib/` |
| Смена FFI-контракта (compute) | `rust/src/api/` → codegen → Dart-вызовы |

Не дублировать парсинг/лемматизацию/offline translate на Dart. User persist — Drift, не FRB storage API.

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
| Web (FRB WASM + Drift) | `flutter run -d chrome --web-header=Cross-Origin-Opener-Policy=same-origin --web-header=Cross-Origin-Embedder-Policy=require-corp` — без COOP/COEP `RustLib.init` падает (`SharedArrayBuffer` / `crossOriginIsolated`); Drift Web assets: `web/sqlite3.wasm`, `web/drift_worker.js` |
| Сборка | `flutter build <platform>` (целевые: apk/ipa/web) |
| Rust check/test | `cargo check` / `cargo test` в `rust/` |
| FRB codegen | `flutter_rust_bridge_codegen generate` (CLI ≈ `2.13.0`) |

Package managers: pub (Dart), Cargo (`rust/`).

---

## How Boot / App Startup Is Organized

1. `main()` → `await RustLib.init()` (`#[frb(init)] init_app` на Rust); при failure — fatal UI, без shell.
2. `runApp(TranslationReaderApp)` → открыть Drift DB (loading → OK / error+retry).
3. Product shell: **Library** (default) + **Vocab**.

Rust:

1. `rust/src/lib.rs` — `mod parse` + `api` + `frb_generated`
2. `rust/src/api/mod.rs` — `simple`, `parse`, …
3. `rust/src/parse/` — subtitle parse core; `api/parse.rs` — тонкий FRB
4. `rust/src/api/simple.rs` — scaffold demo (не product home)

Дальше: lemma / translate вне `api/` + тонкий экспорт. User DB — не в Rust.

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
│   ├── main.dart             ← RustLib.init + runApp
│   ├── app/                  ← MaterialApp, Library|Vocab shell
│   ├── data/                 ← Drift DB, repositories (folders/docs/dict)
│   ├── features/             ← upload (library), reader, vocab, …
│   └── src/rust/             ← GENERATED (не править)
├── rust/
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── parse/            ← subtitle parse core
│       ├── api/              ← публичный FFI API (compute)
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
lib/**  (Flutter UI + Drift data layer)
  → Drift DAOs / repositories   (folders, documents, dictionary_entries)
  → lib/src/rust/api/*  (generated)   # compute only when needed
      → rust/src/api/*  (FFI surface)
          → rust modules: parse / tokenize / lemmatize / translate
```

- User data (library folders/documents, dictionary) — **Drift** source of truth в Flutter.
- Parse / NLP / offline translate — Rust; не дублировать на Dart.
- Не вводить `rusqlite` / `rust/src/db` для пользовательских данных.
- `rust_builder/` не трогать без нужды сборки.

---

## Flutter ↔ Rust Contract

| Dart (generated) | Rust | Сейчас |
|------------------|------|--------|
| `parseSubtitles(bytes:, formatHint:)` | `api::parse::parse_subtitles` | SRT/VTT/ASS → cues + `ParseErrorKind` |
| `processText(input:)` | `process_text` | scaffold demo `to_uppercase` |
| `addNumbers(a:, b:)` | `add_numbers` | scaffold demo `a + b` |
| `RustLib.init()` | `init_app` | `setup_default_user_utils()` |

### Ожидаемые области API (target, ещё нет)

- tokenize / lemmatize → токены + леммы для подсветки и тапа
- translate word/phrase (offline)
- (позже) optional AI explain/translate

Dictionary / library CRUD — **не** FRB storage API: persist через Drift в `lib/`. Lookup-by-lemma для highlight later может читать Drift на Flutter или передавать set лемм в Rust compute — отдельный change.

Менять compute-контракт только через Rust `api/` + codegen + обновление UI и тестов.

---

## Business Entities And Areas (target)

- **Library folder** (`library/folders`) — дерево папок библиотеки (Drift)
- **Library document** (`library/documents`) — subtitle-файл в папке (метаданные + bytes/path; Drift)
- **Subtitle cues** — распарсенные строки/таймкоды (Rust `parse/` → FRB; Reader отображает)
- **Token / Lemma** — единица тапа и ключ подсветки/словаря (Rust NLP)
- **Dictionary entry** (`dictionary/entries`) — лемма, перевод(ы), контекст (Drift persist)
- **Reader session** — открытый документ, позиция скролла, режим split
- **Settings** — языки, (позже) ИИ-провайдер (Drift later)

Размещение: user persist — Drift / Flutter; compute (parse/NLP/translate) — Rust; виджеты и жесты — Flutter.

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

- **Flutter** (`lib/`) — UI Translation Reader + Drift user persistence
- **Rust** (`rust/`) — compute-ядро (parse / NLP / offline translate); без user SQLite
- Согласование compute-контракта — только через FRB codegen, не ручным edit generated-файлов
