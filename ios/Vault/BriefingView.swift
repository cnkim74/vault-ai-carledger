import SwiftUI

/// 1b 브리핑형 — AI 브리핑 + 지출 중심 레저
struct BriefingView: View {
    @ObservedObject var store: VaultStore

    private var shortName: String {
        store.vehicle.name.split(separator: " ").prefix(2).joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            briefing
            spendCard
            leaseCard
            timeline
            Spacer(minLength: 0)
            aiInputBar
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    // 헤더
    private var header: some View {
        HStack {
            (Text("VAULT") + Text(".").foregroundStyle(Theme.gold))
                .font(.system(size: 20, weight: .black))
                .kerning(1)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Theme.green).frame(width: 6, height: 6)
                Text("\(shortName) · \(store.vehicle.battery)% · \(store.vehicle.rangeKm)km")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.silver)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // AI 브리핑
    private var briefing: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.goldGradient)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                )
                .shadow(color: Theme.gold.opacity(0.3), radius: 7, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                (
                    Text("오늘 아침 브리핑이에요. 어제 ")
                    + Text("판교 왕복 76km").bold().foregroundStyle(Theme.gold)
                    + Text("를 자동 기록했고, 약정거리 소진 속도가 빨라요. 이대로면 ")
                    + Text("11월 말 초과").bold().foregroundStyle(Theme.orange)
                    + Text("가 예상돼요.")
                )
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.textStrong)
                .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
                .background(Theme.cardAlt)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    chip("절약 플랜 보기", color: Theme.gold, border: Theme.gold.opacity(0.4))
                    chip("자세히 물어보기", color: Theme.silver, border: Color.white.opacity(0.12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func chip(_ label: String, color: Color, border: Color) -> some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }

    // 월 지출
    private var spendCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7월 총 지출").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text("₩186,400").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("지난달보다 ₩25,300 아꼈어요").font(.system(size: 11)).foregroundStyle(Theme.green)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 5) {
                    bar(38, Color.white.opacity(0.1))
                    bar(52, Color.white.opacity(0.1))
                    bar(44, Color.white.opacity(0.1))
                    bar(58, Color.white.opacity(0.14))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Theme.goldLight, Theme.goldDark], startPoint: .top, endPoint: .bottom))
                        .frame(width: 12, height: 40)
                }
                .frame(height: 64, alignment: .bottom)
                .padding(.top, 6)
            }
            HStack(spacing: 14) {
                legend(Theme.orange, "충전 ₩96,200")
                legend(Theme.gold, "주유 ₩41,000")
                legend(Theme.silver, "기타 ₩49,200")
            }
            .padding(.top, 12)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)), alignment: .top)
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18))
        .background(
            LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    private func bar(_ height: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: height)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.silver)
        }
    }

    // 렌트 약정거리
    private var leaseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("렌트 약정거리").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("초과 위험 · 잔여 \(grouped(store.vehicle.leaseRemainKm))km")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.leaseGradient)
                        .frame(width: geo.size.width * CGFloat(store.vehicle.leasePct ?? 0) / 100)
                }
            }
            .frame(height: 6)
            .padding(.top, 10)
            HStack {
                Text("\(grouped(store.vehicle.leaseDrivenKm ?? 0))km 주행")
                Spacer()
                Text("약정 \(grouped(store.vehicle.leaseLimitKm ?? 0))km")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.orange.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // 이번 주 기록 타임라인
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이번 주 기록").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(Array(store.records.enumerated()), id: \.element.id) { idx, rec in
                    timelineRow(rec, isLast: idx == store.records.count - 1)
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    private func dotColor(_ kind: RecordKind) -> Color {
        switch kind {
        case .charge: return Theme.orange
        case .drive: return Theme.silver
        case .maintenance: return Theme.gold
        }
    }

    private func timelineRow(_ rec: VaultRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(dotColor(rec.kind)).frame(width: 8, height: 8).padding(.top, 5)
                if !isLast {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                }
            }
            .frame(width: 20)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title).font(.system(size: 12.5, weight: .medium))
                    timelineSubtitle(rec)
                }
                Spacer()
                trailing(rec)
            }
            .padding(.bottom, isLast ? 0 : 26)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timelineSubtitle(_ rec: VaultRecord) -> some View {
        let t: Text
        switch rec.kind {
        case .maintenance:
            var s = Text(rec.location ?? "")
            if let tag = rec.tag { s = s + Text(" · \(tag)") }
            t = s
        default:
            var s = Text("\(relativeDay(rec.occurredAt)) \(timeOf(rec.occurredAt))")
            if rec.aiLogged {
                s = s + Text(" · AI 자동기록").foregroundStyle(Theme.gold)
            } else if let tag = rec.tag {
                s = s + Text(" · \(tag)")
            }
            t = s
        }
        return t.font(.system(size: 10.5)).foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private func trailing(_ rec: VaultRecord) -> some View {
        switch rec.kind {
        case .charge:
            if let amount = rec.amountWon {
                Text(won(amount)).font(.system(size: 13, design: .rounded))
            }
        case .drive:
            if let dur = rec.durationMin {
                Text("\(dur)분").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        case .maintenance:
            Text("예약").font(.system(size: 11)).foregroundStyle(Theme.gold)
        }
    }

    // AI 입력 바
    private var aiInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.gold)
            Text("이번 달 충전비 얼마 썼어?")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
            Spacer()
            Image(systemName: "arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(Theme.silver)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.cardAlt)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
