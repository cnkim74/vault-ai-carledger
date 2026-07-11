import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 충전·주유 내역을 사진(AI 인식) 또는 CSV 파일에서 여러 건 한 번에 가져오기.
struct BulkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore

    @State private var rows: [VaultStore.BulkRecord] = []
    @State private var working = false
    @State private var status: String?
    @State private var showPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFile = false
    @State private var saving = false

    private let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "yyyy.M.d"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    HStack(spacing: 10) {
                        sourceButton("사진에서 인식", "camera.viewfinder") { showPhoto = true }
                        sourceButton("CSV 파일", "doc.text") { showFile = true }
                    }
                    if working {
                        HStack(spacing: 8) { ProgressView().tint(Theme.gold); Text("분석 중…").font(pd(12)).foregroundStyle(Theme.muted) }
                            .padding(.vertical, 8)
                    }
                    if let s = status { Text(s).font(pd(11.5)).foregroundStyle(Theme.muted) }

                    if !rows.isEmpty {
                        preview
                    }
                }
                .padding(16)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("내역 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else if !rows.isEmpty {
                        Button(String(format: L("%d건 등록"), rows.count)) { Task { await save() } }
                            .disabled(!store.live)
                    }
                }
            }
            .photosPicker(isPresented: $showPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) { await parseImage(img) }
                    photoItem = nil
                }
            }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { parseCSV(url) }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("사진이나 CSV로 여러 건을 한 번에 등록해요.")
                .font(pd(13, .semibold)).foregroundStyle(Theme.text)
            Text("집·일반 충전기 내역을 채우기 좋아요. (테슬라 슈퍼차저는 자동 임포트)\nCSV 예: 날짜, kWh, 금액, 장소")
                .font(pd(10.5)).foregroundStyle(Theme.muted).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.gold)
                Text(L(title)).font(pd(12.5, .semibold)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.3), lineWidth: 1))
        }
        .disabled(working)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            HStack {
                Text(String(format: L("인식된 %d건"), rows.count)).font(pd(12.5, .semibold))
                Spacer()
                Button { rows = []; status = nil } label: {
                    Text("지우기").font(pd(11.5)).foregroundStyle(Theme.muted)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 10) {
                    Image(systemName: r.kind == .charge ? "bolt.fill" : "fuelpump.fill")
                        .font(.system(size: 13)).foregroundStyle(Theme.gold).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(pd(12.5, .medium)).lineLimit(1)
                        Text(verbatim: df.string(from: r.occurredAt) + (r.location.map { " · \($0)" } ?? ""))
                            .font(pd(10)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    if let a = r.amountWon { Text(won(a)).font(gm(12, .medium)).foregroundStyle(Theme.text) }
                }
                .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: 사진 → AI 다건 추출
    private func parseImage(_ image: UIImage) async {
        working = true; status = nil; defer { working = false }
        guard let b64 = ReceiptScanner.downscaledJPEGBase64(image) else {
            status = L("이미지를 처리할 수 없어요"); return
        }
        let system = """
        You extract MULTIPLE vehicle charging/fuel records from a photo of a history table or list. \
        Return ONLY a JSON object: {"records":[{"date":"YYYY-MM-DD","kind":"charge"|"fuel","kwh":number|null,"amount_won":integer|null,"location":string|null}]}. \
        Parse every visible row. Numbers only (no commas/units). If a field is unreadable use null. Return {"records":[]} if none.
        """
        guard let text = await AIProxy.completeWithImage(system: system,
                prompt: "Extract all rows as JSON.", jpegBase64: b64, maxTokens: 3000,
                model: "claude-haiku-4-5"),
              let data = AIProxy.extractJSON(text),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["records"] as? [[String: Any]] else {
            status = L("인식에 실패했어요. 표가 선명한 사진으로 다시 시도해 주세요."); return
        }
        let parsed = arr.compactMap { rowFrom($0) }
        if parsed.isEmpty { status = L("인식된 내역이 없어요."); return }
        rows = parsed
        status = String(format: L("사진에서 %d건 인식했어요. 확인 후 등록하세요."), parsed.count)
    }

    // MARK: CSV 파싱
    private func parseCSV(_ url: URL) {
        working = true; status = nil; defer { working = false }
        let needStop = url.startAccessingSecurityScopedResource()
        defer { if needStop { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .init(rawValue: 0x80000422)) else {
            status = L("파일을 읽지 못했어요"); return
        }
        var lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { status = L("빈 파일이에요"); return }

        // 헤더로 컬럼 위치 추정 (날짜/kWh/금액/장소). 헤더 없으면 0:날짜 1:kWh 2:금액 3:장소
        var idxDate = 0, idxKwh = 1, idxAmount = 2, idxLoc = 3
        let first = splitCSV(lines[0]).map { $0.lowercased() }
        let looksHeader = first.contains { $0.contains("날짜") || $0.contains("date") || $0.contains("kwh") || $0.contains("금액") }
        if looksHeader {
            for (i, h) in first.enumerated() {
                if h.contains("날짜") || h.contains("date") || h.contains("일시") { idxDate = i }
                else if h.contains("kwh") || h.contains("충전량") || h.contains("전력") { idxKwh = i }
                else if h.contains("금액") || h.contains("요금") || h.contains("amount") || h.contains("원") { idxAmount = i }
                else if h.contains("장소") || h.contains("위치") || h.contains("충전소") || h.contains("location") || h.contains("place") { idxLoc = i }
            }
            lines.removeFirst()
        }

        var out: [VaultStore.BulkRecord] = []
        for line in lines {
            let c = splitCSV(line)
            guard c.count > idxDate, let date = parseDate(c[safe: idxDate]) else { continue }
            let kwh = num(c[safe: idxKwh])
            let amount = num(c[safe: idxAmount]).map { Int($0) }
            let loc = c[safe: idxLoc]?.trimmingCharacters(in: .whitespaces)
            out.append(makeRow(date: date, kind: .charge, kwh: kwh, amountWon: amount,
                               location: (loc?.isEmpty == false ? loc : nil)))
        }
        if out.isEmpty { status = L("인식된 내역이 없어요. 날짜 열을 확인해 주세요."); return }
        rows = out
        status = String(format: L("CSV에서 %d건 읽었어요. 확인 후 등록하세요."), out.count)
    }

    private func save() async {
        saving = true; defer { saving = false }
        do {
            let n = try await store.addRecordsBatch(rows)
            status = String(format: L("%d건 등록됐어요"), n)
            dismiss()
        } catch { status = L("등록 실패: ") + error.localizedDescription }
    }

    // MARK: 헬퍼
    private func rowFrom(_ o: [String: Any]) -> VaultStore.BulkRecord? {
        guard let date = parseDate(o["date"] as? String) else { return nil }
        let kindRaw = (o["kind"] as? String) ?? "charge"
        let kind = RecordKind(rawValue: kindRaw) ?? .charge
        let kwh = num(anyStr(o["kwh"]))
        let amount = num(anyStr(o["amount_won"])).map { Int($0) }
        let loc = (o["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return makeRow(date: date, kind: kind, kwh: kwh, amountWon: amount, location: loc)
    }

    private func makeRow(date: Date, kind: RecordKind, kwh: Double?, amountWon: Int?, location: String?) -> VaultStore.BulkRecord {
        let base = kind == .charge ? L("충전") : L("주유")
        let unit = kind == .charge ? "kWh" : "L"
        let title = kwh.map { "\(base) · \(Int($0) == Int($0.rounded()) ? String(Int($0)) : String(format: "%.1f", $0))\(unit)" } ?? base
        return VaultStore.BulkRecord(kind: kind, title: title, occurredAt: date, amountWon: amountWon, location: location)
    }

    private func anyStr(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? Double { return String(d) }
        if let i = v as? Int { return String(i) }
        return nil
    }
    private func num(_ s: String?) -> Double? {
        guard let s else { return nil }
        let cleaned = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned)
    }
    private func splitCSV(_ line: String) -> [String] {
        line.components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"\t")) }
    }
    private func parseDate(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let fmts = ["yyyy-MM-dd", "yyyy.MM.dd", "yyyy/MM/dd", "yyyy-MM-dd HH:mm", "yyyy.MM.dd HH:mm",
                    "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy년 MM월 dd일", "yyyy년 M월 d일", "MM/dd/yyyy", "yy.MM.dd"]
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR")
        for fmt in fmts { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return ISO8601DateFormatter().date(from: s)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
