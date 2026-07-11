import SwiftUI

/// 차량 기준 주변 슈퍼차저 안내 — 거리·이용 가능 스톨, 탭하면 지도 길안내.
struct NearbySuperchargersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tesla: TeslaService
    var consumer: ConsumerSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if tesla.nearbyLoading {
                        loading
                    } else if let err = tesla.nearbyError {
                        message(err, retry: true)
                    } else if tesla.nearby.isEmpty {
                        message(L("주변 슈퍼차저가 없어요"), retry: true)
                    } else {
                        ForEach(tesla.nearby) { row($0) }
                        Text("차량 현재 위치 기준 · 거리·이용 현황은 실시간이 아닐 수 있어요.")
                            .font(pd(10)).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("가까운 슈퍼차저")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { tesla.consumer = consumer; await tesla.loadNearby() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(tesla.nearbyLoading)
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task { tesla.consumer = consumer; if tesla.nearby.isEmpty { await tesla.loadNearby() } }
    }

    private func row(_ c: TeslaService.NearbyCharger) -> some View {
        Button { openInMaps(c) } label: {
            HStack(spacing: 12) {
                Circle().fill(Theme.red.opacity(0.16)).frame(width: 36, height: 36)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: 15)).foregroundStyle(Theme.red))
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(pd(14, .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let d = c.distanceKm {
                            Label(String(format: "%.1fkm", d), systemImage: "location.fill")
                                .font(pd(11)).foregroundStyle(Theme.silver)
                        }
                        if c.closed {
                            Text("운영 중지").font(pd(10.5, .semibold)).foregroundStyle(Theme.muted)
                        } else if let a = c.availableStalls, let t = c.totalStalls {
                            Text(verbatim: "\(a)/\(t) 이용 가능")
                                .font(pd(11, .medium))
                                .foregroundStyle(a > 0 ? Theme.green : Theme.orange)
                        }
                    }
                }
                Spacer()
                Image(systemName: "map.fill").font(.system(size: 13)).foregroundStyle(Theme.gold)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.gold)
            Text("주변 슈퍼차저를 찾는 중…").font(pd(12)).foregroundStyle(Theme.muted)
            Text("차량이 잠자는 중이면 깨우느라 시간이 걸릴 수 있어요.")
                .font(pd(10.5)).foregroundStyle(Theme.muted2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private func message(_ text: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash").font(.system(size: 30)).foregroundStyle(Theme.muted)
            Text(text).font(pd(13)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            if retry {
                Button { Task { tesla.consumer = consumer; await tesla.loadNearby() } } label: {
                    Text("다시 시도").font(pd(13, .semibold)).foregroundStyle(Theme.gold)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }

    private func openInMaps(_ c: TeslaService.NearbyCharger) {
        let q = c.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Supercharger"
        let urlStr: String
        if let lat = c.lat, let long = c.long {
            urlStr = "http://maps.apple.com/?ll=\(lat),\(long)&q=\(q)"
        } else {
            urlStr = "http://maps.apple.com/?q=\(q)"
        }
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
    }
}
