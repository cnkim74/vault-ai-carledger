import SwiftUI

/// 약정거리 타임라인 선형 그래프.
/// x = 계약 시작 → 종료, y = 0 → 약정거리.
/// - 적정 페이스: (시작,0)→(종료,약정) 회색 점선
/// - 실제 주행: (시작,0)→(오늘,현재) 골드 실선 + 하단 채움
/// - 예측: (오늘,현재)→(종료,만료예상) 점선
/// - 오늘 수직선 + 현재 지점 점
struct LeaseChartView: View {
    let p: LeaseProjection

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxY = Double(max(p.limitKm, p.projectedTotalKm)) * 1.05
            let td = Double(max(p.totalDays, 1))
            let ed = Double(min(p.elapsedDays, p.totalDays))

            let x: (Double) -> CGFloat = { day in CGFloat(day / td) * w }
            let y: (Double) -> CGFloat = { km in h - CGFloat(km / maxY) * h }

            let todayX = x(ed)
            let over = p.overageKm > 0
            let actualColor = p.paceRatioPct > 100 ? Theme.orange : Theme.green

            ZStack {
                // 약정 상한선 (수평)
                Path { pth in
                    pth.move(to: CGPoint(x: 0, y: y(Double(p.limitKm))))
                    pth.addLine(to: CGPoint(x: w, y: y(Double(p.limitKm))))
                }
                .stroke(Theme.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // 적정 페이스 대각선 (회색 점선)
                Path { pth in
                    pth.move(to: CGPoint(x: x(0), y: y(0)))
                    pth.addLine(to: CGPoint(x: x(td), y: y(Double(p.limitKm))))
                }
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                // 실제 주행 하단 채움
                Path { pth in
                    pth.move(to: CGPoint(x: x(0), y: h))
                    pth.addLine(to: CGPoint(x: x(0), y: y(0)))
                    pth.addLine(to: CGPoint(x: todayX, y: y(Double(p.drivenKm))))
                    pth.addLine(to: CGPoint(x: todayX, y: h))
                    pth.closeSubpath()
                }
                .fill(LinearGradient(colors: [actualColor.opacity(0.28), actualColor.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                // 실제 주행 실선
                Path { pth in
                    pth.move(to: CGPoint(x: x(0), y: y(0)))
                    pth.addLine(to: CGPoint(x: todayX, y: y(Double(p.drivenKm))))
                }
                .stroke(actualColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // 예측 (오늘→종료) 점선
                Path { pth in
                    pth.move(to: CGPoint(x: todayX, y: y(Double(p.drivenKm))))
                    pth.addLine(to: CGPoint(x: x(td), y: y(Double(p.projectedTotalKm))))
                }
                .stroke((over ? Theme.orange : actualColor).opacity(0.8),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

                // 오늘 수직선
                Path { pth in
                    pth.move(to: CGPoint(x: todayX, y: 0))
                    pth.addLine(to: CGPoint(x: todayX, y: h))
                }
                .stroke(Color.white.opacity(0.25), lineWidth: 1)

                // 현재 지점 점
                Circle()
                    .fill(actualColor)
                    .frame(width: 8, height: 8)
                    .position(x: todayX, y: y(Double(p.drivenKm)))
                    .overlay(
                        Circle().stroke(Theme.bgTop, lineWidth: 2)
                            .frame(width: 8, height: 8)
                            .position(x: todayX, y: y(Double(p.drivenKm)))
                    )

                // 만료 예상 점
                Circle()
                    .fill(over ? Theme.orange : actualColor)
                    .frame(width: 6, height: 6)
                    .position(x: x(td), y: y(Double(p.projectedTotalKm)))
            }
        }
    }
}
