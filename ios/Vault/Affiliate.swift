import Foundation

/// 제휴(쿠팡 파트너스) 링크 중앙 설정.
///
/// ── 내용 기입 방법 ─────────────────────────────────────────────
/// 1) 쿠팡 파트너스(partners.coupang.com) 로그인 → 상단 "링크 생성"
/// 2) 추천할 상품(예: OBDLink CX)을 쿠팡에서 검색 → 상품 선택 → "링크 만들기"
/// 3) 생성된 단축 URL( https://link.coupang.com/a/XXXXXX )을 복사
/// 4) 아래 `links` 딕셔너리에서 해당 상품명 값(빈 문자열 "")에 붙여넣기
///
/// - 링크가 비어 있으면 쿠팡 "검색" 페이지로 폴백(파트너스 수수료 없음)합니다.
/// - 상품명(키)은 OBDGuideView의 Dongle.name과 정확히 일치해야 합니다.
/// - 링크를 하나라도 넣으면 공정위 고지 문구(`disclosure`)가 화면에 노출됩니다(법적 필수).
enum Affiliate {
    /// 공정위 표시·광고 심사지침상 필수 대가성 고지
    static let disclosure = "쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다."

    /// 상품명 → 쿠팡 파트너스 트래킹 링크. (비어 있으면 검색 폴백)
    /// TODO: 파트너스에서 링크 생성 후 아래 "" 를 교체하세요.
    static let links: [String: String] = [
        "OBDLink CX": "",
        "OBDLink MX+": "",
        "vLinker MC+": "",
        "Veepeak OBDCheck BLE+": "",
        "Vgate iCar Pro BLE 4.0": "",
    ]

    /// 파트너스 링크가 하나라도 설정돼 있으면 true → 고지 문구 노출
    static var hasAnyPartnerLink: Bool { links.values.contains { !$0.isEmpty } }

    /// 특정 상품에 파트너스 링크가 설정됐는지
    static func hasPartnerLink(_ name: String) -> Bool { links[name]?.isEmpty == false }

    /// 구매 링크 — 파트너스 링크가 있으면 그 URL, 없으면 쿠팡 검색으로 폴백
    static func url(for name: String) -> URL? {
        if let s = links[name], !s.isEmpty { return URL(string: s) }
        let enc = "\(name) OBD2 BLE".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.coupang.com/np/search?q=\(enc)")
    }
}
