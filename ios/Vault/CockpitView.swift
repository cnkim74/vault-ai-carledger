import SwiftUI
import PhotosUI

/// 1a 콕핏형 — 차량 상태 히어로 + AI 인사이트
struct CockpitView: View {
    @ObservedObject var store: VaultStore
    @State private var carImage: UIImage? = CarImageStore.load()
    @State private var showPhotoDialog = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showAddRecord = false

    var body: some View {
        VStack(spacing: 0) {
            header
            heroCard
            insightCard
            statCards
            recentRecords
            Spacer(minLength: 0)
            tabBar
        }
        .background(
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .foregroundStyle(Theme.text)
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    carImage = img
                    CarImageStore.save(img)
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddRecordView(store: store)
        }
        .onAppear {
            // 스크린샷/테스트용: SAMPLE_CAR=red|blue|sky
            if carImage == nil,
               let sample = ProcessInfo.processInfo.environment["SAMPLE_CAR"],
               let img = CarImageStore.sample("car-\(sample)") {
                carImage = img
            }
        }
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
                    CarImageStore.clear()
                }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func setSample(_ name: String) {
        guard let img = CarImageStore.sample(name) else { return }
        carImage = img
        CarImageStore.save(img)
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
                Text("AI 인사이트")
                    .font(pd(11, .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.gold)
                (
                    Text("심야 요금제로 충전 시간대를 옮기면 이번 달 ")
                    + Text("₩38,200").bold().foregroundStyle(Theme.gold)
                    + Text(" 절약할 수 있어요.")
                )
                .font(pd(13))
                .lineSpacing(3)
                .foregroundStyle(Theme.textStrong)
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
                Text("7월 지출").font(pd(11)).foregroundStyle(Theme.muted)
                Text("₩186,400").font(gm(19, .bold))
                Text("지난달 대비 −12%").font(pd(11)).foregroundStyle(Theme.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("약정거리").font(pd(11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(store.vehicle.leasePct ?? 0)%").font(pd(10)).foregroundStyle(Theme.orange)
                }
                (
                    Text(grouped(store.vehicle.leaseDrivenKm ?? 0))
                        .font(gm(19, .bold))
                    + Text(" /\(grouped(store.vehicle.leaseLimitKm ?? 0))km")
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
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

    // 탭바
    private var tabBar: some View {
        HStack(alignment: .bottom) {
            tabItem(icon: "house", label: "홈", active: true)
            Spacer()
            tabItem(icon: "line.3.horizontal", label: "기록")
            Spacer()
            Button {
                showAddRecord = true
            } label: {
                Circle()
                    .fill(Theme.goldGradient)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    )
                    .shadow(color: Theme.gold.opacity(0.35), radius: 9, y: 6)
            }
            .offset(y: -14)
            Spacer()
            tabItem(icon: "chart.bar", label: "통계")
            Spacer()
            tabItem(icon: "car", label: "차고")
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            Theme.bgTop.opacity(0.9)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(icon: String, label: String, active: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17))
            Text(label)
                .font(pd(9.5))
        }
        .foregroundStyle(active ? Theme.gold : Theme.muted)
        .frame(minWidth: 48)
    }
}
