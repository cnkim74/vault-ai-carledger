import Foundation

/// 사용자 프로필 — 이름을 로컬(UserDefaults)에 보관.
/// 첫 실행 시 이름이 없으면 온보딩 시트로 입력받는다.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var name: String

    private static let key = "vault.userName"

    init() {
        name = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    var isSet: Bool { !name.isEmpty }

    /// 헤더 인사용 (예: "지훈님", 미설정 시 "회원님")
    var greetingName: String {
        if name.isEmpty { return L("회원님") }
        return AppLocale.languageCode.hasPrefix("ko") ? "\(name)님" : name
    }

    /// 아바타 이니셜 (한글 첫 글자 또는 영문 앞 2자)
    var initials: String {
        guard let first = name.first else { return "ME" }
        if first.isLetter && first.unicodeScalars.first!.value > 0x3130 {
            return String(first)   // 한글 한 글자
        }
        return String(name.prefix(2)).uppercased()
    }

    func save(_ newName: String) {
        name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(name, forKey: Self.key)
    }
}
