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

    /// 추천 용품 파트너스 링크(선택). 키=검색 키워드. 없으면 쿠팡 검색으로 폴백.
    /// TODO: 자주 팔리는 용품은 파트너스에서 링크 생성 후 여기에 추가하세요.
    static let productLinks: [String: String] = [:]
    static func productURL(_ keyword: String) -> URL? {
        if let s = productLinks[keyword], !s.isEmpty { return URL(string: s) }
        let enc = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.coupang.com/np/search?q=\(enc)")
    }
}

/// 정비 항목에 대응하는 추천 용품
struct MaintenanceProduct: Identifiable {
    var id: String { title }
    let title: String       // 표시명
    let keyword: String     // 쿠팡 검색어
    let icon: String        // SF Symbol
}

/// 정비 예정 항목 → 쿠팡 추천 용품 매핑
enum MaintenanceShop {
    static func product(for item: String) -> MaintenanceProduct? {
        func has(_ s: String) -> Bool { item.contains(s) }
        if has("엔진오일") || has("오일필터") { return .init(title: "엔진오일·오일필터", keyword: "자동차 엔진오일", icon: "drop.fill") }
        if has("미션오일") || has("기어오일") { return .init(title: "미션·기어오일", keyword: "미션오일", icon: "drop.fill") }
        if has("에어컨 필터") || has("실내필터") { return .init(title: "에어컨(실내) 필터", keyword: "자동차 에어컨필터", icon: "wind") }
        if has("에어필터") || has("에어클리너") { return .init(title: "엔진 에어필터", keyword: "자동차 에어필터", icon: "wind") }
        if has("연료필터") { return .init(title: "연료필터", keyword: "자동차 연료필터", icon: "fuelpump.fill") }
        if has("타이어") { return .init(title: "타이어", keyword: "자동차 타이어", icon: "circle.circle.fill") }
        if has("브레이크 패드") { return .init(title: "브레이크 패드", keyword: "자동차 브레이크 패드", icon: "octagon.fill") }
        if has("브레이크 오일") || has("브레이크액") { return .init(title: "브레이크액", keyword: "브레이크액 DOT4", icon: "drop.fill") }
        if has("와이퍼") { return .init(title: "와이퍼 블레이드", keyword: "자동차 와이퍼", icon: "cloud.rain.fill") }
        if has("배터리") { return .init(title: "자동차 배터리", keyword: "자동차 배터리", icon: "minus.plus.batteryblock.fill") }
        if has("스파크") || has("점화") { return .init(title: "점화플러그", keyword: "점화플러그", icon: "bolt.fill") }
        if has("냉각수") || has("부동액") { return .init(title: "부동액(냉각수)", keyword: "자동차 부동액", icon: "snowflake") }
        if has("체인") { return .init(title: "체인 루브", keyword: "오토바이 체인루브", icon: "link") }
        return nil
    }
    /// 정비 예정 목록 → 중복 제거된 추천 용품
    static func products(for items: [String]) -> [MaintenanceProduct] {
        var seen = Set<String>(); var out: [MaintenanceProduct] = []
        for i in items { if let p = product(for: i), !seen.contains(p.title) { seen.insert(p.title); out.append(p) } }
        return out
    }
}
