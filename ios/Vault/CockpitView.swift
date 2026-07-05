import SwiftUI
import PhotosUI

/// 1a 콕핏형 — 차량 상태 히어로 + AI 인사이트
struct CockpitView: View {
    @ObservedObject var store: VaultStore
    @ObservedObject var insight: InsightService
    @State private var carImage: UIImage?
    @State private var showPhotoDialog = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var weather = WeatherService()
    @StateObject private var prediction = PredictionService()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                heroCard
                insightCard
                statCards
                leaseProjectionCard
                predictionCard
                StationsCard(store: store, weather: weather)
                    .padding(.top, 12)
                recentRecords
            }
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .foregroundStyle(Theme.text)
        .task(id: store.vehicle.id) {
            await prediction.predict(vehicle: store.vehicle, records: store.records, placeName: weather.city)
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    carImage = img
                    CarImageStore.save(img, for: store.vehicle.id)
                }
            }
        }
        .onChange(of: store.vehicle.id) { _, newID in
            carImage = CarImageStore.load(for: newID) ?? envSampleImage()
        }
        .onAppear {
            weather.start()
            carImage = CarImageStore.load(for: store.vehicle.id) ?? envSampleImage()
        }
    }

    /// 스크린샷/테스트용: SAMPLE_CAR=red|blue|sky
    private func envSampleImage() -> UIImage? {
        guard let sample = ProcessInfo.processInfo.environment["SAMPLE_CAR"] else { return nil }
        return CarImageStore.sample("car-\(sample)")
    }

    // 헤더
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VAULT")
                    .font(pd(22, .black))
                    .kerning(1)
                    .foregroundStyle(Theme.goldGradient)
                HStack(spacing: 5) {
                    Text("좋은 아침이에요, 지훈님")
                        .font(pd(11))
                        .foregroundStyle(Theme.muted2)
                    if store.live {
                        Text("· Supabase 연결됨")
                            .font(pd(11, .semibold))
                            .foregroundStyle(Theme.green)
                    }
                }
                if let temp = weather.tempC {
                    HStack(spacing: 5) {
                        Image(systemName: weather.symbol)
                            .font(.system(size: 10))
                            .symbolRenderingMode(.multicolor)
                        Text("\(weather.city) \(temp)° · \(weather.label)")
                            .font(pd(11))
                            .foregroundStyle(Theme.silver)
                        if let score = weather.carWashScore {
                            washBadge(score: score, grade: weather.carWashGrade)
                        }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                circleButton {
                    Image(systemName: "bell")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.silver)
                }
                circleButton {
                    Text("JH")
                        .font(pd(12, .semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // 세차지수 배지
    private func washBadge(score: Int, grade: String) -> some View {
        let color: Color = score >= 60 ? Theme.green : (score >= 40 ? Theme.gold : Theme.orange)
        return HStack(spacing: 3) {
            Image(systemName: "drop.fill").font(.system(size: 8))
            Text("세차 \(score) · \(grade)").font(pd(10, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func circleButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.06))
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(Circle())
    }

    // 차량 히어로
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.vehicle.name)
                        .font(gm(17, .medium))
                    Text("\(store.vehicle.plate ?? "") · \(store.vehicle.fuelType)")
                        .font(pd(11))
                        .kerning(0.5)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("주차 중")
                    .font(pd(10.5))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.gold.opacity(0.4), lineWidth: 1))
            }

            // 차량 사진 슬롯 — 탭하면 앨범/샘플 선택
            photoSlot
                .padding(.top, 12)
                .padding(.bottom, 4)

            HStack(spacing: 16) {
                batteryRing
                VStack(spacing: 6) {
                    statRow(label: "주행 가능 거리", value: "\(store.vehicle.rangeKm) km")
                    statRow(label: "누적 주행", value: "\(grouped(store.vehicle.odometerKm)) km")
                    HStack {
                        Text("완충까지").font(pd(12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("충전 중 아님").font(pd(12)).foregroundStyle(Theme.silver)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(
            ZStack {
                LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                // 골드 글로우
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.gold.opacity(0.14), .clear],
                            center: .center, startRadius: 0, endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .offset(x: 120, y: 110)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var photoSlot: some View {
        Group {
            if let img = carImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.gold.opacity(0.7))
                            Text("탭해서 내 차 사진을 선택하세요")
                                .font(pd(11))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(Color.white.opacity(0.18))
                    )
                    .frame(height: 130)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { showPhotoDialog = true }
        .confirmationDialog("차량 사진", isPresented: $showPhotoDialog, titleVisibility: .visible) {
            Button("앨범에서 선택") { showPicker = true }
            Button("샘플 · 레드") { setSample("car-red") }
            Button("샘플 · 블루") { setSample("car-blue") }
            Button("샘플 · 스카이") { setSample("car-sky") }
            if carImage != nil {
                Button("사진 제거", role: .destructive) {
                    carImage = nil
                    CarImageStore.clear(for: store.vehicle.id)
                }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func setSample(_ name: String) {
        guard let img = CarImageStore.sample(name) else { return }
        carImage = img
        CarImageStore.save(img, for: store.vehicle.id)
    }

    private var batteryRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(store.vehicle.battery) / 100)
                .stroke(Theme.gold, lineWidth: 7)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Theme.card)
                .padding(7)
            Text("\(store.vehicle.battery)%")
                .font(gm(16, .bold))
                .foregroundStyle(Theme.gold)
        }
        .frame(width: 74, height: 74)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(pd(12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(gm(12, .medium))
        }
    }

    // AI 인사이트
    private var insightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.goldGradient)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("AI 인사이트")
                        .font(pd(11, .semibold))
                        .kerning(0.5)
                        .foregroundStyle(Theme.gold)
                    if insight.loading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.gold)
                    }
                }
                Group {
                    if let tip = insight.tip {
                        Text(tip)
                    } else {
                        (
                            Text("심야 요금제로 충전 시간대를 옮기면 이번 달 ")
                            + Text("₩38,200").bold().foregroundStyle(Theme.gold)
                            + Text(" 절약할 수 있어요.")
                        )
                    }
                }
                .font(pd(13))
                .lineSpacing(3)
                .foregroundStyle(Theme.textStrong)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(
            LinearGradient(
                colors: [Theme.gold.opacity(0.12), Theme.gold.opacity(0.04)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.gold.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // 지출 + 약정거리
    private var statCards: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.monthlySpend?.month ?? 7)월 지출").font(pd(11)).foregroundStyle(Theme.muted)
                Text(won(store.monthlySpend?.total ?? 186400)).font(gm(19, .bold))
                spendDelta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))

            secondStatCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var spendDelta: some View {
        if let s = store.monthlySpend, let pct = s.deltaPct {
            let down = pct <= 0
            Text("지난달 대비 \(down ? "−" : "+")\(abs(pct))%")
                .font(pd(11))
                .foregroundStyle(down ? Theme.green : Theme.orange)
        } else if store.monthlySpend != nil {
            Text("첫 지출 기록").font(pd(11)).foregroundStyle(Theme.muted)
        } else {
            Text("지난달 대비 −12%").font(pd(11)).foregroundStyle(Theme.green)
        }
    }

    // 두 번째 통계 카드: 약정거리(리스/렌트) 또는 구매가(구매)
    @ViewBuilder
    private var secondStatCard: some View {
        Group {
            if let limit = store.vehicle.leaseLimitKm, limit > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("약정거리").font(pd(11)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(store.vehicle.leasePct ?? 0)%").font(pd(10)).foregroundStyle(Theme.orange)
                    }
                    (
                        Text(grouped(store.vehicle.leaseDriven))
                            .font(gm(19, .bold))
                        + Text(" /\(grouped(limit))km")
                            .font(pd(11))
                            .foregroundStyle(Theme.muted)
                    )
                    .padding(.top, 4)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Theme.leaseGradient)
                                .frame(width: geo.size.width * CGFloat(store.vehicle.leasePct ?? 0) / 100)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.vehicle.ownership.label).font(pd(11)).foregroundStyle(Theme.muted)
                    if let price = store.vehicle.purchasePriceWon {
                        Text(won(price)).font(gm(19, .bold))
                        Text("구매가").font(pd(11)).foregroundStyle(Theme.muted)
                    } else {
                        Text("\(grouped(store.vehicle.odometerKm))").font(gm(19, .bold))
                        Text("누적 주행 km").font(pd(11)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    // 계약서 기반 약정거리 초과 예측
    @ViewBuilder
    private var leaseProjectionCard: some View {
        if let p = store.vehicle.leaseProjection() {
            let over = p.overageKm > 0
            let accent = over ? Theme.orange : Theme.green
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: over ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accent)
                        Text("약정거리 예측")
                            .font(pd(12, .semibold))
                    }
                    Spacer()
                    Text(p.isOverPace ? "과속 페이스" : "안전 페이스")
                        .font(pd(10.5, .semibold))
                        .foregroundStyle(accent)
                }

                // 만료 시 예상 주행 vs 약정
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("만료 시 예상")
                        .font(pd(11)).foregroundStyle(Theme.muted)
                    Text("\(grouped(p.projectedTotalKm))km")
                        .font(gm(18, .bold))
                    Text("/ 약정 \(grouped(p.limitKm))km")
                        .font(pd(10.5)).foregroundStyle(Theme.muted)
                }

                // 이중 게이지: 시간 진행(회색) 위에 거리 진행(골드→오렌지)
                GeometryReader { geo in
                    let distRatio = min(1.3, Double(p.drivenKm) / Double(p.limitKm))
                    let allowRatio = min(1.0, Double(p.allowedToDateKm) / Double(p.limitKm))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        // 오늘까지 허용 페이스 마커
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(width: geo.size.width * CGFloat(allowRatio))
                        Capsule().fill(Theme.leaseGradient)
                            .frame(width: geo.size.width * CGFloat(min(1.0, distRatio)))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("현재 \(grouped(p.drivenKm))km · 하루 \(Int(p.dailyPaceKm.rounded()))km")
                        .font(pd(10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(over ? "예상 초과 +\(grouped(p.overageKm))km" : "예상 여유 \(grouped(-p.overageKm))km")
                        .font(pd(11, .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.3), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // AI 예상 이동거리
    @ViewBuilder
    private var predictionCard: some View {
        if let km = prediction.weeklyKm {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.gold.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gold)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("이번 주 예상 이동")
                            .font(pd(12, .semibold))
                        Text(prediction.isAI ? "AI" : "예상")
                            .font(pd(8.5, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.goldGradient)
                            .clipShape(Capsule())
                    }
                    if let reason = prediction.reason {
                        Text(reason).font(pd(10)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Text("\(grouped(km))km")
                    .font(gm(18, .bold))
                    .foregroundStyle(Theme.gold)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 16))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // 최근 기록
    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("최근 기록").font(pd(13, .semibold))
                Spacer()
                Text("전체 보기").font(pd(11)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 0)

            ForEach(store.records.filter { $0.kind != .maintenance }.prefix(2)) { rec in
                recordRow(rec)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func recordRow(_ rec: VaultRecord) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(rec.kind == .charge ? Theme.orange.opacity(0.14) : Theme.silver.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: rec.kind == .charge ? "bolt.fill" : "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(rec.kind == .charge ? Theme.orange : Theme.silver)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(rec.title).font(pd(12.5, .medium))
                subtitleText(rec)
            }
            Spacer()
            if rec.kind == .charge, let amount = rec.amountWon {
                Text(won(amount)).font(gm(13, .medium))
            } else if let tag = rec.tag {
                Text(tag).font(pd(11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func subtitleText(_ rec: VaultRecord) -> some View {
        var t = Text("\(relativeDay(rec.occurredAt))")
        if rec.kind == .charge {
            t = t + Text(" \(timeOf(rec.occurredAt))")
            if let loc = rec.location { t = t + Text(" · \(loc)") }
            if rec.aiLogged { t = t + Text(" · AI 자동기록").foregroundStyle(Theme.gold) }
        } else {
            if let dist = rec.distanceKm { t = t + Text(" · \(String(format: "%.1f", dist))km") }
            if let dur = rec.durationMin { t = t + Text(" · \(dur)분") }
        }
        return t.font(pd(10.5)).foregroundStyle(Theme.muted)
    }

}
