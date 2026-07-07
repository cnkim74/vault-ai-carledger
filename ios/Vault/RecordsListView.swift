import SwiftUI

/// 기록 탭 — 전체 기록 타임라인
struct RecordsListView: View {
    @ObservedObject var store: VaultStore
    @State private var editingRecord: VaultRecord?
    @State private var showChecklist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("기록")
                    .font(pd(22, .black))
                    .kerning(1)
                Spacer()
                Button { showChecklist = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist").font(.system(size: 11))
                        Text("정비 체크리스트").font(pd(12, .semibold))
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .overlay(Capsule().stroke(Theme.gold.opacity(0.4), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if store.records.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.muted)
                    Text("아직 기록이 없어요")
                        .font(pd(13))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.records) { rec in
                            Button { editingRecord = rec } label: { row(rec) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgTop.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .sheet(item: $editingRecord) { rec in
            AddRecordView(store: store, editing: rec)
        }
        .sheet(isPresented: $showChecklist) {
            MaintenanceChecklistView(store: store)
        }
    }

    private func iconInfo(_ kind: RecordKind) -> (symbol: String, color: Color) {
        switch kind {
        case .charge: return ("bolt.fill", Theme.orange)
        case .fuel: return ("fuelpump.fill", Theme.gold)
        case .drive: return ("clock", Theme.silver)
        case .maintenance: return ("wrench.and.screwdriver", Theme.gold)
        }
    }

    private func row(_ rec: VaultRecord) -> some View {
        let info = iconInfo(rec.kind)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(info.color.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: info.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(info.color)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(rec.title).font(pd(12.5, .medium))
                subtitle(rec)
            }
            Spacer()
            trailing(rec)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func subtitle(_ rec: VaultRecord) -> some View {
        var t: Text
        if rec.kind == .maintenance {
            t = Text(rec.location ?? "")
            if let tag = rec.tag { t = t + Text(" · \(tag)") }
        } else {
            t = Text("\(relativeDay(rec.occurredAt)) \(timeOf(rec.occurredAt))")
            if let loc = rec.location { t = t + Text(" · \(loc)") }
            if let dist = rec.distanceKm { t = t + Text(" · \(String(format: "%.1f", dist))km") }
            if rec.aiLogged { t = t + Text(" · AI 자동기록").foregroundStyle(Theme.gold) }
            else if let tag = rec.tag { t = t + Text(" · \(tag)") }
        }
        return t.font(pd(10.5)).foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private func trailing(_ rec: VaultRecord) -> some View {
        if let amount = rec.amountWon {
            Text(won(amount)).font(gm(13, .medium))
        } else if let dur = rec.durationMin {
            Text(verbatim: String(format: L("%d분"), dur)).font(pd(11)).foregroundStyle(Theme.muted)
        } else if rec.kind == .maintenance {
            Text("예약").font(pd(11)).foregroundStyle(Theme.gold)
        }
    }
}
