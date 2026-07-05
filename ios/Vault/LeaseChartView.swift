import SwiftUI

/// 약정거리 예측 — 가장 단순한 진도율 막대.
/// 트랙 = max(약정, 만료예상). 골드 = 0~약정 진행분, 빨강 = 약정 초과분.
/// 흰 눈금 = 현재 주행 위치, 흰 세로선 = 약정(100%) 기준선.
struct LeaseChartView: View {
    let p: LeaseProjection

    var body: some View {
        let limit = Double(max(p.limitKm, 1))
        let proj = Double(max(p.projectedTotalKm, 0))
        let driven = Double(max(p.drivenKm, 0))
        let maxV = max(limit, proj)
        let projRatio = min(proj / maxV, 1)
        let limitRatio = min(limit / maxV, 1)
        let drivenRatio = min(driven / maxV, 1)
        let over = proj > limit

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .leading) {
                // 트랙
                Capsule().fill(Color.white.opacity(0.08))

                // 0~약정 진행분 (골드)
                Capsule()
                    .fill(Theme.goldGradient)
                    .frame(width: max(0, w * min(projRatio, limitRatio)))

                // 약정 초과분 (빨강)
                if over {
                    Capsule()
                        .fill(Theme.red)
                        .frame(width: max(0, w * (projRatio - limitRatio)))
                        .offset(x: w * limitRatio)
                }

                // 현재 주행 위치 눈금
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: h + 6)
                    .offset(x: min(max(w * drivenRatio - 1.25, 0), w - 2.5))

                // 약정(100%) 기준선
                if over {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1.5, height: h)
                        .offset(x: w * limitRatio - 0.75)
                }
            }
        }
    }
}
