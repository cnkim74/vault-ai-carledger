import SwiftUI
import PhotosUI

/// 1a 콕핏형 — 차량 상태 히어로 + AI 인사이트
struct CockpitView: View {
    @ObservedObject var store: VaultStore
    @ObservedObject var insight: InsightService
    @ObservedObject var profile: ProfileStore
    var onEditProfile: () -> Void = {}
    var onShowRecords: () -> Void = {}
    @State private var editingRecord: VaultRecord?
    @State private var carImage: UIImage?
    @State private var showPhotoDialog = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var weather = WeatherService()
    @StateObject private var prediction = PredictionService()
    @StateObject private var calendar = CalendarService()
    @StateObject private var notif = NotificationService()
    @State private var showBatteryEdit = false
    @State private var showOdometerEdit = false
    @State private var batteryInput = ""
    @State private var odometerInput = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                weatherCard
                heroCard
                insightCard
                DestinationCard(calendar: calendar)
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
        .task { await calendar.load() }
        .task(id: store.vehicle.id) {
            await notif.refreshIfEnabled(store: store, weather: weather)
        }
        .sheet(item: $editingRecord) { rec in
            AddRecordView(store: store, editing: rec)
        }
        .alert("현재 배터리", isPresented: $showBatteryEdit) {
            TextField("0~100", text: $batteryInput).keyboardType(.numberPad)
            Button("저장") {
                if let v = Int(batteryInput), (0...100).contains(v) {
                    Task { try? await store.updateVehicle(.init(battery: v)) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 배터리 잔량(%)을 입력하세요. 주행 가능 거리가 자동 계산돼요.")
        }
        .alert("누적 주행거리", isPresented: $showOdometerEdit) {
            TextField("km", text: $odometerInput).keyboardType(.numberPad)
            Button("저장") {
                if let v = Int(odometerInput), v >= 0 {
                    Task { try? await store.updateVehicle(.init(odometer_km: v)) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("계기판의 현재 누적 주행거리(km)를 입력하세요.")
        }
    }

    // 날씨 대시보드 카드
    private var weatherCard: some View {
        Group {
            if let temp = weather.tempC {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: weather.symbol)
                            .font(.system(size: 34))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(temp)°").font(gm(26, .bold))
                                Text(weather.label).font(pd(13)).foregroundStyle(Theme.silver)
                            }
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill").font(.system(size: 9)).foregroundStyle(Theme.muted)
                                Text(weather.city).font(pd(11)).foregroundStyle(Theme.muted)
                                if !weather.washReason.isEmpty {
                                    Text("· \(weather.washReason)").font(pd(11)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        Spacer()
                        if let score = weather.carWashScore {
                            washGauge(score: score, grade: weather.carWashGrade)
                        }
                    }
                    if let advice = weather.carAdvice {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.gold)
                            Text(advice).font(pd(11, .semibold)).foregroundStyle(Theme.gold)
                        }
                        .padding(.top, 10)
                        .padding(.leading, 2)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .background(
                    LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.07), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
    }

    // 세차지수 게이지 (원형)
    private func washGauge(score: Int, grade: String) -> some View {
        let color: Color = score >= 60 ? Theme.green : (score >= 40 ? Theme.gold : Theme.orange)
        return VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4).frame(width: 46, height: 46)
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text("\(score)").font(gm(14, .bold)).foregroundStyle(color)
            }
            Text(verbatim: "\(L("세차")) \(grade)").font(pd(9)).foregroundStyle(color)
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
                Text("\(greeting), \(profile.greetingName)")
                    .font(pd(11))
                    .foregroundStyle(Theme.muted2)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    Task { await notif.toggle(store: store, weather: weather) }
                } label: {
                    circleButton {
                        Image(systemName: notif.enabled ? "bell.fill" : "bell")
                            .font(.system(size: 14))
                            .foregroundStyle(notif.enabled ? Theme.gold : Theme.silver)
                    }
                }
                Button(action: onEditProfile) {
                    circleButton {
                        Text(profile.initials)
                            .font(pd(12, .semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // 시간대 인사말
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return L("좋은 아침이에요")
        case 11..<17: return L("좋은 오후예요")
        case 17..<22: return L("좋은 저녁이에요")
        default: return L("안녕하세요")
        }
    }

    private func circleButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.06))
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(Circle())
    }

    // 상태 배지: 실시간 데이터(테슬라 연결+동기화)가 있을 때만 표시.
    // 데이터 소스가 없으면(미연결) 오해를 주지 않도록 숨긴다.
    @ViewBuilder
    private var statusBadge: some View {
        if teslaConnected, let live = store.liveStatus {
            let color: Color = {
                switch live {
                case .driving: return Theme.green
                case .charging: return Theme.orange
                case .parked: return Theme.gold
                }
            }()
            HStack(spacing: 4) {
                Image(systemName: live.icon).font(.system(size: 9))
                Text(live.label).font(pd(10.5))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
        }
    }

    // 차량 히어로
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.vehicle.name)
                        .font(gm(17, .medium))
                    Text("\(store.vehicle.plate ?? "") · \(L(store.vehicle.fuelType))")
                        .font(pd(11))
                        .kerning(0.5)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                statusBadge
            }

            // 차량 사진(비율 채움) + 배터리 도넛을 같은 줄에, 중간 여백 없이
            HStack(spacing: 14) {
                photoSlot(height: 128)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                // 테슬라 자동연결이면 수정 불가(값은 자동 동기화), 아니면 탭해서 편집
                if teslaConnected {
                    batteryRing(editable: false).padding(.top, 12)
                } else {
                    Button {
                        batteryInput = "\(store.vehicle.battery)"
                        showBatteryEdit = true
                    } label: { batteryRing(editable: true) }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }

            // 상세 스탯 (풀폭)
            VStack(spacing: 8) {
                statRow(label: "주행 가능 거리", value: "\(store.vehicle.rangeKm) km")
                // 테슬라 자동연결이면 누적 주행도 수정 불가
                if teslaConnected {
                    HStack {
                        Text("누적 주행").font(pd(13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(grouped(store.vehicle.odometerKm)) km")
                            .font(gm(13, .medium)).foregroundStyle(Theme.text)
                    }
                } else {
                    Button {
                        odometerInput = "\(store.vehicle.odometerKm)"
                        showOdometerEdit = true
                    } label: {
                        HStack {
                            HStack(spacing: 4) {
                                Text("누적 주행").font(pd(13)).foregroundStyle(Theme.muted)
                                Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Theme.gold)
                            }
                            Spacer()
                            Text("\(grouped(store.vehicle.odometerKm)) km")
                                .font(gm(13, .medium)).foregroundStyle(Theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text("완충 시 주행").font(pd(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("503 km").font(pd(13)).foregroundStyle(Theme.silver)
                }
            }
            .padding(.top, 14)
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
    private func photoSlot(height: CGFloat = 130) -> some View {
        Group {
            if let img = carImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        VStack(spacing: 5) {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.gold.opacity(0.7))
                            Text("사진 선택")
                                .font(pd(10))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(Color.white.opacity(0.18))
                    )
                    .frame(height: height)
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

    // 테슬라 자동연결 여부 (연결 시 배터리·주행거리는 자동 동기화 → 수동 수정 숨김)
    private var teslaConnected: Bool {
        UserDefaults.standard.bool(forKey: "tesla.connected")
    }

    // 배터리 잔량별 색상: 20%↑ 녹색 / 10~20% 노랑 / 10%↓ 빨강
    private var batteryColor: Color {
        let b = store.vehicle.battery
        if b >= 20 { return Theme.green }
        if b >= 10 { return Theme.yellow }
        return Theme.red
    }

    private func batteryRing(editable: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(store.vehicle.battery) / 100)
                .stroke(batteryColor, lineWidth: 7)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Theme.card)
                .padding(7)
            VStack(spacing: 1) {
                Text("\(store.vehicle.battery)%")
                    .font(gm(16, .bold))
                    .foregroundStyle(batteryColor)
                if editable {
                    Image(systemName: "pencil").font(.system(size: 8)).foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: 74, height: 74)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(L(label)).font(pd(12)).foregroundStyle(Theme.muted)
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
                Text(verbatim: String(format: L("%d월 지출"), store.monthlySpend?.month ?? 7)).font(pd(11)).foregroundStyle(Theme.muted)
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
            let paceOver = p.paceRatioPct > 100
            let paceColor = paceOver ? Theme.orange : Theme.green
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: paceOver ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(paceColor)
                        Text("약정거리 예측")
                            .font(pd(12, .semibold))
                    }
                    Spacer()
                    Text(p.isOverPace ? "과속 페이스" : "안전 페이스")
                        .font(pd(10.5, .semibold))
                        .foregroundStyle(paceColor)
                }

                // 오늘 기준 적정 대비 현재 % (핵심 지표)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("오늘 기준 적정 대비")
                        .font(pd(11)).foregroundStyle(Theme.muted)
                    Text("\(p.paceRatioPct)%")
                        .font(gm(24, .bold))
                        .foregroundStyle(paceColor)
                    Text(verbatim: paceOver ? String(format: L("· %d%% 빠름"), p.paceRatioPct - 100) : L("· 여유"))
                        .font(pd(10.5)).foregroundStyle(paceColor.opacity(0.9))
                }

                // 진도율 막대 (만료 시 예상 대비 약정, 초과분은 빨강)
                LeaseChartView(p: p)
                    .frame(height: 16)
                    .padding(.top, 6)

                // 막대 범례 (0% · 현재 · 약정 100%)
                HStack {
                    Text("0")
                        .font(pd(9)).foregroundStyle(Theme.muted)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 5, height: 5)
                        Text("현재 \(p.projectedTotalKm > p.limitKm ? Int(Double(p.drivenKm) / Double(max(p.limitKm,1)) * 100) : p.paceRatioPct)%")
                            .font(pd(9, .semibold)).foregroundStyle(Theme.silver)
                    }
                    Spacer()
                    Text("약정 100%")
                        .font(pd(9, .semibold))
                        .foregroundStyle(over ? Theme.red : Theme.muted)
                }

                // 적정/실제 주행 비교
                HStack {
                    Text(verbatim: String(format: L("오늘 적정 %@km · 현재 %@km"), grouped(p.allowedToDateKm), grouped(p.drivenKm)))
                        .font(pd(10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(verbatim: String(format: L("하루 %d/%dkm"), Int(p.dailyPaceKm.rounded()), p.allowedDailyKm))
                        .font(pd(10)).foregroundStyle(Theme.muted)
                }

                // 만료 예상 + 초과/여유
                HStack {
                    Text(verbatim: String(format: L("만료 시 예상 %@km / 약정 %@km"), grouped(p.projectedTotalKm), grouped(p.limitKm)))
                        .font(pd(10.5)).foregroundStyle(Theme.silver)
                    Spacer()
                    Text(over ? "초과 +\(grouped(p.overageKm))km" : "여유 \(grouped(-p.overageKm))km")
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
                Button(action: onShowRecords) {
                    HStack(spacing: 2) {
                        Text("전체 보기").font(pd(11))
                        Image(systemName: "chevron.right").font(.system(size: 9))
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 0)

            if store.records.isEmpty {
                Text("아직 기록이 없어요").font(pd(11)).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            ForEach(store.records.prefix(3)) { rec in
                Button { editingRecord = rec } label: { recordRow(rec) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func recordRow(_ rec: VaultRecord) -> some View {
        let icon: String
        let color: Color
        switch rec.kind {
        case .charge: icon = "bolt.fill"; color = Theme.orange
        case .fuel: icon = "fuelpump.fill"; color = Theme.gold
        case .drive: icon = "clock"; color = Theme.silver
        case .maintenance: icon = "wrench.and.screwdriver.fill"; color = Theme.green
        }
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(rec.title).font(pd(12.5, .medium))
                subtitleText(rec)
            }
            Spacer()
            if let amount = rec.amountWon {
                Text(won(amount)).font(gm(13, .medium))
            } else if let dur = rec.durationMin {
                Text(verbatim: String(format: L("%d분"), dur)).font(pd(11)).foregroundStyle(Theme.muted)
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
        if rec.kind == .charge || rec.kind == .fuel {
            t = t + Text(" \(timeOf(rec.occurredAt))")
            if let loc = rec.location { t = t + Text(" · \(loc)") }
            if rec.aiLogged { t = t + Text(" · AI 자동기록").foregroundStyle(Theme.gold) }
        } else {
            if let dist = rec.distanceKm { t = t + Text(" · \(String(format: "%.1f", dist))km") }
            if let dur = rec.durationMin { t = t + Text(verbatim: String(format: L(" · %d분"), dur)) }
        }
        return t.font(pd(10.5)).foregroundStyle(Theme.muted)
    }

}
