import SwiftUI

/// OBD-II 동글 자동 연동 안내 — 브랜드 무관 자동 기록의 차별점 소개 + 호환 동글 추천.
/// 실제 BLE 연동은 추후 제공, 지금은 안내/온보딩 화면.
struct OBDGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var premium: PremiumStore
    @ObservedObject var store: VaultStore
    @State private var showPaywall = false
    @State private var showConnect = false

    // 호환 동글 (iOS BLE) — 탭 시 검색으로 이동
    private struct Dongle: Identifiable {
        let id = UUID()
        let name: String, tagline: String, price: String, badge: String?
    }
    private let dongles: [Dongle] = [
        .init(name: "OBDLink CX", tagline: "BLE 5.1 · 안정성 최고 · EV/CAN 우수", price: "~$60", badge: "추천"),
        .init(name: "OBDLink MX+", tagline: "프로토콜 폭넓음 · 제조사 PID 강함", price: "~$100", badge: nil),
        .init(name: "vLinker MC+", tagline: "가성비 · iOS 지원 명시", price: "~$40", badge: nil),
        .init(name: "Veepeak OBDCheck BLE+", tagline: "입문용 저가 · iOS 호환", price: "~$25", badge: "가성비"),
        .init(name: "Vgate iCar Pro BLE 4.0", tagline: "저가 · 자동 슬립", price: "~$30", badge: nil),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    steps
                    dataChips
                    iosNote
                    dongleList
                    evNote
                    cta
                }
                .padding(20)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("OBD 동글 연동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) { PaywallSheet(premium: premium) }
        .sheet(isPresented: $showConnect) { OBDConnectView(store: store) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.gold.opacity(0.14))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "car.rear.and.tire.marks").font(.system(size: 22)).foregroundStyle(Theme.gold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("브랜드 상관없이 자동 기록").font(gm(18, .bold))
                    Text("OBD 동글 하나면 연료·주행거리·정비코드를 자동으로").font(pd(12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func stepRow(_ n: Int, _ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.gold)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(pd(13.5, .semibold))
                Text(desc).font(pd(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이렇게 동작해요").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            stepRow(1, "puzzlepiece.extension.fill", "동글을 OBD 단자에 꽂기", "운전석 아래 진단 단자에 연결 (2005년 이후 차량 대부분)")
            stepRow(2, "wave.3.right", "블루투스로 연결", "앱이 BLE 동글을 찾아 자동 연결")
            stepRow(3, "arrow.triangle.2.circlepath", "시동 시 자동 기록", "주유·주행·정비 데이터가 자동으로 차계부에 반영")
        }
    }

    private var dataChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("무엇이 채워지나요").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(["연료 잔량", "주행거리", "VIN 자동인식", "정비 경고(DTC)", "주행 트립"], id: \.self) { item in
                    Text(L(item))
                        .font(pd(12)).foregroundStyle(Theme.gold)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Theme.gold.opacity(0.12)).clipShape(Capsule())
                }
            }
        }
    }

    private var iosNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.gold)
            Text("iPhone은 BLE(저전력 블루투스) 동글만 지원해요. 저가 ‘블루투스 클래식’ ELM327은 iOS에서 동작하지 않으니 아래 목록에서 고르세요.")
                .font(pd(11.5)).foregroundStyle(Theme.silver)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.25), lineWidth: 1))
    }

    private var dongleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iOS 호환 추천 동글").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            ForEach(dongles) { d in dongleCard(d) }
            // 공정위 대가성 고지 (파트너스 링크가 설정된 경우에만 노출)
            if Affiliate.hasAnyPartnerLink {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(Theme.muted2)
                    Text(Affiliate.disclosure).font(pd(9.5)).foregroundStyle(Theme.muted2)
                }
                .padding(.top, 2)
            }
        }
    }

    private func dongleCard(_ d: Dongle) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 15)).foregroundStyle(Theme.silver))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.name).font(pd(13.5, .semibold))
                    if let b = d.badge {
                        Text(L(b)).font(pd(9, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.goldGradient).clipShape(Capsule())
                    }
                }
                Text(d.tagline).font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                Text(d.price).font(gm(10.5, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { openBuy(d.name) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill").font(.system(size: 10))
                    Text("구매").font(pd(11, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.goldGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private var evNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.car.fill").font(.system(size: 13)).foregroundStyle(Theme.silver)
            Text("전기차 배터리 잔량은 표준 OBD로 안 나와요. 전기차는 테슬라 연동이 더 정확하고, 동글은 내연기관차에 강력해요.")
                .font(pd(11)).foregroundStyle(Theme.muted)
        }
    }

    private var cta: some View {
        VStack(spacing: 8) {
            Button {
                if premium.isPremium { showConnect = true } else { showPaywall = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right.circle.fill").font(.system(size: 16))
                    Text(premium.isPremium ? "동글 연결하기" : "프리미엄으로 동글 연동")
                        .font(pd(15, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.goldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text("BLE(저전력 블루투스) 동글이 필요해요.").font(pd(10)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 4)
    }

    private func openBuy(_ name: String) {
        if let url = Affiliate.url(for: name) { UIApplication.shared.open(url) }
    }
}
