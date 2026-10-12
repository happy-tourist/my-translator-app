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

**Сейчас:** product shell Library + Vocabulary; user data в **Drift** (`lib/data/`, `schemaVersion` **4**). Library open → `loadBytes` → FRB `parseSubtitles` → cues-first **Reader** (`lib/features/reader/`) with optional **split** (second subtitle file, time-nearest sync, hidden linked translation via `translationDocumentId`). Single-token tap → bottom CTA + add/edit vocab sheet; **morph lemma highlight** on original pane (`tokenize_cues` → `mark_vocab_tokens`, WordNet `lemma_key`). Rust: `parse/` + `tokenize/` + `lemmatize/` + thin `api/` (плюс scaffold `process_text` / `add_numbers`, не home UI).

**Ещё target:** phrase-span highlight / phrase Add; offline translate; Rust cue pairing for index-aligned split — следующие changes.

---

## What It Is Used For

### Основные сценарии

1. **Чтение субтитров** (сейчас) — загрузка SRT / VTT / ASS(SSA); парсинг в Rust; построчное отображение в Flutter.
2. **Изучение слов по тапу** (сейчас: single-token sheet; фраза — target) — тап по слову → лемма + «добавить/редактировать в словаре»; выделение фразы — later.
3. **Подсветка знакомых слов** (сейчас) — записи словаря подсвечиваются в оригинале; матч по morph lemma (`run` / `running` / `ran` = одно слово).
4. **Разделённый экран** (сейчас MVP) — сверху оригинал, снизу файл перевода; sync по ближайшему `startMs`, позже — по индексу при pairing.
5. **Работа с ИИ** (опционально, позже) — перевод фраз, фразовые глаголы, контекст; разные провайдеры через API.
6. **Офлайн-перевод** (target) — базовый перевод слов/фраз без интернета.

### Ключевые функции

- Парсинг субтитров: SRT, VTT, ASS/SSA (сейчас)
- Токенизация + EN WordNet лемматизация + mark (сейчас); RU morph — later
- Личный словарь: переводы + контекст + `surface_key` (сейчас, Drift schema 4)
- Подсветка сохранённых слов с учётом морфологии (сейчас, original pane)
- Тап → bottom CTA + add/edit vocab sheet (сейчас); офлайн-карточка перевода — later
- Выделение фразы → перевод фразы целиком (target)
- Split view: оригинал + файл перевода, sync scroll (MVP: nearest `startMs`)
- Опциональный ИИ для перевода/объяснений (later)
- Локальное хранение (папки/документы библиотеки, словарь, настройки later) — **Drift** в Flutter (`lib/`)
- Работа офлайн

### Сейчас в коде

- Flutter: shell **Library** (папки / import / open→Reader + best-effort linked translation) + **Vocab** (CRUD); cues-first Reader with single-token tap→sheet, morph lemma highlight, split toggle / load-delete translation / time sync + reading-anchor resume; Drift schema v4 (`surface_key` on dictionary entries, stub→morph migration via `lemmaKeysForSurfaces`) + repositories (`attachTranslation` / `saveReadingAnchor` / `loadBytes` / content store)
- Rust: `parse/` + `tokenize/` (panko) + `lemmatize/` (EN WordNet) + FRB `parse_subtitles` / `tokenize_cues` / `mark_vocab_tokens` / `lemma_keys_for_surfaces` (no pairing API); scaffold `process_text` / `add_numbers` / `init_app` ещё в crate
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
- **Web local run:** всегда `flutter run -d chrome --web-port=5555` + COOP/COEP headers (`http://localhost:5555`). Порт входит в browser origin — без фиксированного порта Drift OPFS выглядит «пустым» после рестарта. Канон команды: meta skill `work-with-env-deploy`.

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

**Сейчас:** Library (папки / import / open + linked translation restore), cues-first Reader (таймкоды + текст, single-token tap→vocab sheet, morph lemma highlight on original pane, optional horizontal split + sync), Vocab CRUD.

**Target (later):** phrase multi-token highlight/Add, offline word card gloss, index-aligned paired split, настройки (языки, опциональный ИИ).

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
| Словарь CRUD + контекст (`dictionary/entries`) | Drift в `lib/` (persist); morph lemma keys — Rust FRB (`lemma_keys_for_surfaces` / `TokenDto.lemma_key`) |
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

1. `rust/src/lib.rs` — `mod parse` + `tokenize` + `lemmatize` + `api` + `frb_generated`
2. `rust/src/api/mod.rs` — `simple`, `parse`, `tokenize`, …
3. `rust/src/parse/` — subtitle parse core; `api/parse.rs` — тонкий FRB
4. `rust/src/tokenize/` + `lemmatize/` — panko spans + EN WordNet morph keys; thin exports on `api/tokenize.rs`
5. `rust/src/api/simple.rs` — scaffold demo (не product home)

Дальше: offline translate вне `api/` + тонкий экспорт. User DB — не в Rust.

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
│       ├── tokenize/         ← panko word spans
│       ├── lemmatize/        ← EN WordNet morph keys + mark helpers
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
| `tokenizeCues(texts:)` | `api::tokenize::tokenize_cues` | word tokens + char spans + `lemma_key` (`is_in_vocab=false`) |
| `markVocabTokens(cues:, vocabLemmas:)` | `api::tokenize::mark_vocab_tokens` | sets `is_in_vocab` from morph lemma set |
| `lemmaKeysForSurfaces(surfaces:)` | `api::tokenize::lemma_keys_for_surfaces` | surface→morph key (Vocab / stub→morph migration) |
| `processText(input:)` | `process_text` | scaffold demo `to_uppercase` |
| `addNumbers(a:, b:)` | `add_numbers` | scaffold demo `a + b` |
| `RustLib.init()` | `init_app` | `setup_default_user_utils()` |

### Ожидаемые области API (target, ещё нет)

- translate word/phrase (offline)
- (позже) optional AI explain/translate

Dictionary / library CRUD — **не** FRB storage API: persist через Drift в `lib/`. Highlight membership: Flutter loads morph lemmas from Drift and passes them to `markVocabTokens`.

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
