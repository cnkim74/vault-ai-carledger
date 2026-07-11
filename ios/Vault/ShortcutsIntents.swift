import AppIntents
import Foundation

/// 단축어(Shortcuts)에서 호출하는 "지출 기록 추가" 인텐트.
/// 카드 승인 문자 자동화: 문자 수신 → 금액/가맹점 추출 → 이 인텐트 실행 → 앱에 기록 자동 저장.
struct AddSpendRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "지출 기록 추가"
    static var description = IntentDescription("카드 승인 문자의 금액·가맹점으로 차계부 기록을 자동으로 추가합니다.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "금액(원)") var amount: Int
    @Parameter(title: "종류", default: .fuel) var kind: RecordKindOption
    @Parameter(title: "가맹점/메모") var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount)원 \(\.$kind) 기록 추가") { \.$merchant }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await QuickRecord.add(amount: amount, kind: kind.recordKind, title: merchant)
        return .result(dialog: IntentDialog(stringLiteral:
            ok ? "기록을 추가했어요." : "먼저 앱에서 차량을 등록해 주세요."))
    }
}

/// 단축어 파라미터용 기록 종류
enum RecordKindOption: String, AppEnum {
    case fuel, charge, maintenance, other
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "기록 종류"
    static var caseDisplayRepresentations: [RecordKindOption: DisplayRepresentation] = [
        .fuel: "주유", .charge: "충전", .maintenance: "정비", .other: "기타",
    ]
    var recordKind: RecordKind {
        switch self {
        case .fuel: return .fuel
        case .charge: return .charge
        case .maintenance: return .maintenance
        case .other: return .drive
        }
    }
}

/// Siri/단축어 노출용
struct WheeletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddSpendRecordIntent(),
            phrases: [
                "\(.applicationName)에 지출 기록 추가",
                "\(.applicationName) 기록 추가",
            ],
            shortTitle: "지출 기록 추가",
            systemImageName: "creditcard.fill"
        )
    }
}

/// 인텐트에서 앱 UI 없이 기록을 저장 (익명 세션 Keychain 공유 → 본인 계정으로 격리 저장).
enum QuickRecord {
    @MainActor
    static func add(amount: Int, kind: RecordKind, title: String?) async -> Bool {
        let session = ConsumerSession()
        await session.start()
        guard let token = await session.validToken(),
              let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return false }
        // 앱에서 마지막으로 선택한 차량에 기록
        guard let vid = UserDefaults.standard.string(forKey: "vault.selectedVehicleID"), !vid.isEmpty else { return false }

        struct Ins: Encodable {
            let vehicle_id: String; let kind: String; let title: String
            let occurred_at: String; let amount_won: Int; let ai_logged: Bool
        }
        let body = Ins(
            vehicle_id: vid.lowercased(), kind: kind.rawValue,
            title: (title?.isEmpty == false ? title! : kind.label),
            occurred_at: ISO8601DateFormatter().string(from: Date()),
            amount_won: amount, ai_logged: true
        )
        var req = URLRequest(url: base.appendingPathComponent("rest/v1/records"))
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(body)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
        return true
    }
}
