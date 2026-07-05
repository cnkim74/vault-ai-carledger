import Foundation

/// 런타임 문자열(String 변수·enum rawValue·서비스 메시지)을 String Catalog로 지역화.
/// SwiftUI `Text("리터럴")`은 자동 지역화되지만, String 값은 안 되므로 이 헬퍼로 감싼다.
/// 카탈로그에 키가 없으면 원문(한국어)을 그대로 반환.
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}

/// 현재 기기 언어 코드 (AI 응답 언어 지정용). 예: "ko", "en", "ja", "zh-Hans"
enum AppLocale {
    static var languageCode: String {
        Locale.preferredLanguages.first.map { String($0) } ?? "ko"
    }
    /// AI 프롬프트용 사람이 읽는 언어명
    static var aiLanguageName: String {
        let c = (Locale.preferredLanguages.first ?? "ko").lowercased()
        if c.hasPrefix("en") { return "English" }
        if c.hasPrefix("ja") { return "Japanese (日本語)" }
        if c.hasPrefix("zh") { return "Simplified Chinese (简体中文)" }
        return "Korean (한국어)"
    }
}
