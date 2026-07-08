import SwiftUI

/// 홈 "업무 모드" — 배정받은 회사(Fleet) 차량 전용 간소 화면.
/// 개인 분석(리스·중고시세 등) 대신 기사에게 필요한 것만: 이번 달 비용·정비·빠른 기록.
struct WorkVehicleHomeView: View {
    @ObservedObject var fleet: FleetStore
    let vehicle: FleetVehicle
    var showsSwitcher: Bool = false   // 상단 스위처가 이름/배지를 보여줄 땐 히어로에서 생략
    @State private var showAddRecord = false

    private var records: [FleetRecord] {
        fleet.records.filter { $0.fleet_vehicle_id == vehicle.id }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            heroCard
            costRow
            if let w = serviceWarning { warnBanner(w.text, w.color) }
            addButton
            recentRecords
        }
    }

    // 업무 차량 히어로
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.14)).frame(width: 46, height: 46)
                    .overlay(Image(systemName: vehicle.vehicleCategory.icon).font(.system(size: 19)).foregroundStyle(Theme.gold))
                let modelStr = [vehicle.maker, vehicle.model].compactMap { $0 }.joined(separator: " ")
                VStack(alignment: .leading, spacing: 3) {
                    if showsSwitcher {
                        // 스위처가 번호판+배지를 보여주므로 여기선 모델/소속만
                        Text(modelStr.isEmpty ? (fleet.fleet?.name ?? L("업무 차량")) : modelStr).font(gm(16, .bold))
                        if !modelStr.isEmpty, let org = fleet.fleet?.name {
                            Text(org).font(pd(11)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    } else {
                        Text(vehicle.plate ?? vehicle.name ?? "-").font(gm(17, .bold))
                        Text(modelStr.isEmpty ? (fleet.fleet?.name ?? "") : "\(modelStr) · \(L(vehicle.fuel ?? ""))")
                            .font(pd(11)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if !showsSwitcher {
                    Text("업무").font(pd(9.5, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.gold).clipShape(Capsule())
                }
            }
            HStack(spacing: 10) {
                stat(L("누적 주행"), "\(grouped(vehicle.odometerKm))km", Theme.text)
                if let r = vehicle.serviceRemaining {
                    stat(L("다음 정비"),
                         r < 0 ? String(format: L("%dkm 초과"), -r) : String(format: L("%dkm 남음"), r),
                         r < 0 ? Theme.red : (r <= 2000 ? Theme.orange : Theme.green))
                } else {
                    stat(L("소속"), fleet.fleet?.name ?? "-", Theme.silver)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 8)
    }
    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
            Text(value).font(gm(15, .bold)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // 이번 달 비용
    private var costRow: some View {
        HStack {
            Label("이번 달 비용", systemImage: "wonsign.circle.fill").font(pd(12, .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            Text(won(fleet.monthlyCost(vehicleId: vehicle.id))).font(gm(18, .bold)).foregroundStyle(Theme.gold)
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12)
    }

    // 정비 경고
    private var serviceWarning: (text: String, color: Color)? {
        guard let r = vehicle.serviceRemaining else { return nil }
        if r < 0 { return (String(format: L("%@ 정비 시기가 지났어요."), vehicle.plate ?? vehicle.model ?? L("차량")), Theme.red) }
        if r <= 2000 { return (String(format: L("정비가 임박했어요 (%dkm 남음)."), r), Theme.orange) }
        return nil
    }
    private func warnBanner(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 12)).foregroundStyle(color)
            Text(text).font(pd(11.5, .semibold)).foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(color.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12)
    }

    // 빠른 기록 추가
    private var addButton: some View {
        Button { showAddRecord = true } label: {
            Label("주유·주행 기록 추가", systemImage: "plus.circle.fill")
                .font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16).padding(.top, 12)
        .sheet(isPresented: $showAddRecord) { FleetRecordAddView(fleet: fleet, vehicle: vehicle) }
    }

    // 최근 기록
    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 기록").font(pd(13, .semibold)).padding(.bottom, 0)
            if records.isEmpty {
                Text("아직 기록이 없어요").font(pd(11)).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            ForEach(records.prefix(5)) { r in recordRow(r) }
        }
        .padding(.horizontal, 16).padding(.top, 16)
    }
    private func recordRow(_ r: FleetRecord) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.14)).frame(width: 32, height: 32)
                .overlay(Image(systemName: icon(r.recordKind)).font(.system(size: 13)).foregroundStyle(Theme.gold))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title ?? r.recordKind.label).font(pd(12.5, .medium))
                Text(Self.df.string(from: r.date)).font(pd(10.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let a = r.amount_won { Text(won(a)).font(gm(13, .medium)) }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func icon(_ k: RecordKind) -> String {
        switch k { case .charge: return "bolt.fill"; case .fuel: return "fuelpump.fill"; case .drive: return "clock"; case .maintenance: return "wrench.and.screwdriver.fill" }
    }
    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f }()
}
