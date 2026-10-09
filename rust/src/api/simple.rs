/// Принимает строку и возвращает её в верхнем регистре.
/// В будущем здесь может быть логика перевода или лемматизации.
pub fn process_text(input: String) -> String {
    // В реальном приложении здесь будет вызов вашей логики на Rust:
    // парсинг, лемматизация, поиск в словаре и т.д.
    input.to_uppercase()
}

/// Функция для примера с числами.
pub fn add_numbers(a: i32, b: i32) -> i32 {
    a + b
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
