//! Domain + global-API coverage for TO-01…TO-06 and TO-08.
//!
//! Tests that touch the process-global engine are serialized (ORT + shared slot).

use std::sync::{Mutex, MutexGuard, OnceLock};

use super::{
    clear_engine_for_test, init_offline_translate, install_engine_for_test,
    is_offline_translate_ready, translate_text, GlossResult, NamedAssetBytes, OfflineTranslator,
    TranslateError,
};

struct EchoFake;

impl OfflineTranslator for EchoFake {
    fn translate(
        &self,
        text: &str,
        _source_lang: &str,
        _target_lang: &str,
    ) -> Result<GlossResult, TranslateError> {
        Ok(GlossResult {
            primary_gloss: format!("RU:{text}"),
        })
    }
}

struct FailingFake;

impl OfflineTranslator for FailingFake {
    fn translate(
        &self,
        _text: &str,
        _source_lang: &str,
        _target_lang: &str,
    ) -> Result<GlossResult, TranslateError> {
        Err(TranslateError::InferenceFailed)
    }
}

fn test_lock() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

/// Hold the lock for the whole test; clear global engine before/after.
fn reset() -> MutexGuard<'static, ()> {
    let guard = test_lock();
    clear_engine_for_test();
    guard
}

/// [TO-03] Empty / whitespace-only → EmptyQuery.
#[test]
fn to03_empty_query_rejected() {
    let _lock = reset();
    install_engine_for_test(Box::new(EchoFake));
    assert_eq!(
        translate_text("", "en", "ru").unwrap_err(),
        TranslateError::EmptyQuery
    );
    assert_eq!(
        translate_text("   \t\n", "en", "ru").unwrap_err(),
        TranslateError::EmptyQuery
    );
}

/// [TO-06] Pair other than EN→RU → UnsupportedLanguagePair.
#[test]
fn to06_unsupported_language_pair() {
    let _lock = reset();
    install_engine_for_test(Box::new(EchoFake));
    assert_eq!(
        translate_text("hello", "ru", "en").unwrap_err(),
        TranslateError::UnsupportedLanguagePair
    );
    assert_eq!(
        translate_text("hello", "en", "de").unwrap_err(),
        TranslateError::UnsupportedLanguagePair
    );
    // Case-insensitive success path still works with fake.
    let ok = translate_text("hello", "EN", "RU").expect("casefold en→ru");
    assert_eq!(ok.primary_gloss, "RU:hello");
}

/// [TO-04] No init → EngineUnavailable.
#[test]
fn to04_engine_unavailable_without_init() {
    let _lock = reset();
    assert!(!is_offline_translate_ready());
    assert_eq!(
        translate_text("hello", "en", "ru").unwrap_err(),
        TranslateError::EngineUnavailable
    );
}

/// [TO-05] Engine up, inference fails → InferenceFailed.
#[test]
fn to05_inference_failed() {
    let _lock = reset();
    install_engine_for_test(Box::new(FailingFake));
    assert!(is_offline_translate_ready());
    assert_eq!(
        translate_text("hello", "en", "ru").unwrap_err(),
        TranslateError::InferenceFailed
    );
}

/// Fake path covering word gloss contract used by TO-01.
#[test]
fn to01_word_gloss_via_fake() {
    let _lock = reset();
    install_engine_for_test(Box::new(EchoFake));
    let r = translate_text("hello", "en", "ru").expect("word");
    assert!(!r.primary_gloss.is_empty());
    assert_eq!(r.primary_gloss, "RU:hello");
}

/// Fake path covering phrase gloss contract used by TO-02.
#[test]
fn to02_phrase_gloss_via_fake() {
    let _lock = reset();
    install_engine_for_test(Box::new(EchoFake));
    let r = translate_text("good morning", "en", "ru").expect("phrase");
    assert!(!r.primary_gloss.is_empty());
    assert_eq!(r.primary_gloss, "RU:good morning");
}

/// [TO-08] Missing required asset → EngineUnavailable; empty bytes → same.
#[test]
fn to08_init_missing_or_empty_assets() {
    let _lock = reset();
    let err = init_offline_translate(vec![NamedAssetBytes {
        name: "tokenizer.json".into(),
        bytes: b"{}".to_vec(),
    }]);
    assert_eq!(err.unwrap_err(), TranslateError::EngineUnavailable);
    assert!(!is_offline_translate_ready());

    let err = init_offline_translate(vec![
        NamedAssetBytes {
            name: "tokenizer.json".into(),
            bytes: Vec::new(),
        },
        NamedAssetBytes {
            name: "encoder_model_uint8.onnx".into(),
            bytes: vec![1],
        },
        NamedAssetBytes {
            name: "decoder_model_uint8.onnx".into(),
            bytes: vec![1],
        },
    ]);
    assert_eq!(err.unwrap_err(), TranslateError::EngineUnavailable);
}

#[cfg(not(target_arch = "wasm32"))]
mod real_ort {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn model_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models/opus-mt-en-ru")
    }

    fn load_assets() -> Vec<NamedAssetBytes> {
        let dir = model_dir();
        vec![
            NamedAssetBytes {
                name: "tokenizer.json".into(),
                bytes: fs::read(dir.join("tokenizer.json")).expect("tokenizer.json"),
            },
            NamedAssetBytes {
                name: "encoder_model_uint8.onnx".into(),
                bytes: fs::read(dir.join("onnx/encoder_model_uint8.onnx"))
                    .expect("encoder"),
            },
            NamedAssetBytes {
                name: "decoder_model_uint8.onnx".into(),
                bytes: fs::read(dir.join("onnx/decoder_model_uint8.onnx"))
                    .expect("decoder"),
            },
        ]
    }

    /// [TO-08] Valid asset bytes → init Ok + ready.
    #[test]
    fn to08_init_with_real_asset_bytes() {
        let _lock = reset();
        init_offline_translate(load_assets()).expect("init real assets");
        assert!(is_offline_translate_ready());
    }

    /// [TO-01] Real engine: English word → non-empty RU gloss.
    #[test]
    fn to01_real_word_hello() {
        let _lock = reset();
        init_offline_translate(load_assets()).expect("init");
        let r = translate_text("hello", "en", "ru").expect("hello");
        assert!(!r.primary_gloss.trim().is_empty());
        assert!(
            r.primary_gloss
                .chars()
                .any(|c| ('\u{0400}'..='\u{04FF}').contains(&c)),
            "expected Cyrillic, got {:?}",
            r.primary_gloss
        );
    }

    /// [TO-02] Real engine: English phrase → one non-empty gloss.
    #[test]
    fn to02_real_phrase_good_morning() {
        let _lock = reset();
        init_offline_translate(load_assets()).expect("init");
        let r = translate_text("good morning", "EN", "RU").expect("phrase");
        assert!(!r.primary_gloss.trim().is_empty());
    }

    /// Spike regression: same path as former `spike_opus_mt_en_ru_hello_offline`.
    #[test]
    fn spike_opus_mt_en_ru_hello_offline() {
        let _lock = reset();
        init_offline_translate(load_assets()).expect("init");
        let hello = translate_text("hello", "en", "ru").expect("hello");
        println!("spike hello -> {:?}", hello.primary_gloss);
        let phrase = translate_text("good morning", "en", "ru").expect("phrase");
        println!("spike phrase -> {:?}", phrase.primary_gloss);
        assert!(!hello.primary_gloss.trim().is_empty());
        assert!(!phrase.primary_gloss.trim().is_empty());
    }
}
