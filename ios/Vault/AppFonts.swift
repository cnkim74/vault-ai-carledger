import SwiftUI
import CoreText

/// 번들된 폰트(Pretendard, GmarketSans)를 런타임에 등록한다.
/// GENERATE_INFOPLIST_FILE 환경에서는 UIAppFonts 키를 쓸 수 없어 CoreText로 직접 등록.
enum AppFonts {
    static func registerAll() {
        for ext in ["otf", "ttf"] {
            let urls = (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? [])
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

/// 전역 텍스트 배율 — 가독성을 위해 전반적으로 조금 크게.
let textScale: CGFloat = 1.1

/// Pretendard — 본문/UI 텍스트 (디자인 스펙)
func pd(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let name: String
    if weight == .black { name = "Pretendard-Black" }
    else if weight == .bold || weight == .heavy { name = "Pretendard-Bold" }
    else if weight == .semibold { name = "Pretendard-SemiBold" }
    else if weight == .medium { name = "Pretendard-Medium" }
    else { name = "Pretendard-Regular" }
    return .custom(name, size: size * textScale)
}

/// GmarketSans — 숫자/강조 (디자인 스펙)
func gm(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    let name = (weight == .bold || weight == .black || weight == .heavy)
        ? "GmarketSansTTFBold"
        : "GmarketSansTTFMedium"
    return .custom(name, size: size * textScale)
}
