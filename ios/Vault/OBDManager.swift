import Foundation
import CoreBluetooth

/// OBD-II 동글에서 읽어온 값.
struct OBDReading {
    var fuelPercent: Int?
    var odometerKm: Int?
    var tripKm: Double?
    var vin: String?
}

/// ELM327 계열 BLE 동글과 통신. 스캔 → 연결 → 초기화(AT) → PID 조회 → 파싱.
/// 동글마다 서비스/캐릭터리스틱 UUID가 달라, 쓰기+알림 가능한 캐릭터리스틱을 탐색해 사용한다.
/// 하드웨어별 편차가 있어 실사용 시 튜닝이 필요할 수 있음.
@MainActor
final class OBDManager: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, scanning, connecting, initializing, reading, done, failed }

    @Published var phase: Phase = .idle
    @Published var found: [CBPeripheral] = []
    @Published var status: String?
    @Published var reading: OBDReading?
    @Published var poweredOff = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var buffer = ""
    private var pending: CheckedContinuation<String, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        found.removeAll(); reading = nil; status = nil
        guard central.state == .poweredOn else { poweredOff = true; return }
        phase = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
        // 12초 후 스캔 중지
        Task { try? await Task.sleep(nanoseconds: 12_000_000_000); if phase == .scanning { central.stopScan() } }
    }

    func connect(_ p: CBPeripheral) {
        central.stopScan()
        phase = .connecting
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; writeChar = nil; notifyChar = nil; phase = .idle
    }

    // MARK: - ELM327 명령 실행

    /// 한 명령을 보내고 '>' 프롬프트까지의 응답을 반환 (타임아웃 4초).
    private func send(_ cmd: String) async -> String {
        guard let peripheral, let writeChar else { return "" }
        buffer = ""
        let data = Data((cmd + "\r").utf8)
        let type: CBCharacteristicWriteType =
            writeChar.properties.contains(.write) ? .withResponse : .withoutResponse

        let response: String = await withCheckedContinuation { cont in
            pending = cont
            peripheral.writeValue(data, for: writeChar, type: type)
            Task { try? await Task.sleep(nanoseconds: 4_000_000_000); resumePending(with: buffer) }
        }
        return response
    }

    private func resumePending(with s: String) {
        guard let p = pending else { return }
        pending = nil
        p.resume(returning: s)
    }

    /// 초기화 후 주요 PID 조회.
    private func runSession() async {
        phase = .initializing; status = L("동글 초기화 중…")
        _ = await send("ATZ")        // reset
        _ = await send("ATE0")       // echo off
        _ = await send("ATL0")       // linefeed off
        _ = await send("ATSP0")      // 자동 프로토콜

        phase = .reading; status = L("차량 데이터 읽는 중…")
        var r = OBDReading()
        r.fuelPercent = parseFuel(await send("012F"))
        r.tripKm = parseTrip(await send("0131"))
        r.odometerKm = parseOdometer(await send("01A6"))
        r.vin = parseVIN(await send("0902"))

        reading = r
        phase = .done
        status = (r.fuelPercent == nil && r.odometerKm == nil && r.tripKm == nil && r.vin == nil)
            ? L("이 차량은 표준 OBD 값을 제공하지 않아요.")
            : L("읽기 완료")
    }

    // MARK: - 파싱 (16진 바이트 추출)

    /// 응답에서 mode+pid 뒤의 데이터 바이트 배열을 추출.
    private func dataBytes(_ raw: String, respPrefix: String) -> [Int] {
        // 공백·프롬프트·개행 정리 → 2자리 hex 토큰
        let cleaned = raw.uppercased()
            .replacingOccurrences(of: ">", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let tokens = cleaned.split(separator: " ").map(String.init).filter { $0.count == 2 && Int($0, radix: 16) != nil }
        // respPrefix(예: "412F") 위치를 찾아 그 뒤를 데이터로
        let joined = tokens.joined()
        guard let range = joined.range(of: respPrefix) else { return [] }
        let after = String(joined[range.upperBound...])
        var bytes: [Int] = []
        var i = after.startIndex
        while let next = after.index(i, offsetBy: 2, limitedBy: after.endIndex), next <= after.endIndex {
            if let b = Int(after[i..<next], radix: 16) { bytes.append(b) }
            i = next
        }
        return bytes
    }

    private func parseFuel(_ raw: String) -> Int? {
        let b = dataBytes(raw, respPrefix: "412F")
        guard let a = b.first else { return nil }
        return Int((Double(a) * 100.0 / 255.0).rounded())
    }
    private func parseTrip(_ raw: String) -> Double? {
        let b = dataBytes(raw, respPrefix: "4131")
        guard b.count >= 2 else { return nil }
        return Double(b[0] * 256 + b[1])   // km
    }
    private func parseOdometer(_ raw: String) -> Int? {
        let b = dataBytes(raw, respPrefix: "41A6")
        guard b.count >= 4 else { return nil }
        let v = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
        return Int((Double(v) / 10.0).rounded())   // PID A6: 0.1km 단위
    }
    private func parseVIN(_ raw: String) -> String? {
        // 49 02 ... 이후 ASCII 문자(영숫자 17자) 추출 — best effort
        let cleaned = raw.uppercased().replacingOccurrences(of: ">", with: " ")
        let tokens = cleaned.split(whereSeparator: { " \r\n".contains($0) }).map(String.init)
            .filter { $0.count == 2 && Int($0, radix: 16) != nil }
        let joined = tokens.joined()
        guard let range = joined.range(of: "4902") else { return nil }
        var chars = ""
        var i = joined.index(range.upperBound, offsetBy: 0)
        while let next = joined.index(i, offsetBy: 2, limitedBy: joined.endIndex), next <= joined.endIndex {
            if let b = Int(joined[i..<next], radix: 16), b >= 0x30, b <= 0x5A {
                let c = Character(UnicodeScalar(b)!)
                if c.isLetter || c.isNumber { chars.append(c) }
            }
            i = next
        }
        let vin = String(chars.suffix(17))
        return vin.count >= 11 ? vin : nil
    }
}

// MARK: - CoreBluetooth 델리게이트 (main 큐)

extension OBDManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state != .poweredOn { poweredOff = true }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard peripheral.name?.isEmpty == false else { return }
            if !found.contains(where: { $0.identifier == peripheral.identifier }) {
                found.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            status = L("서비스 탐색 중…")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { phase = .failed; status = L("연결에 실패했어요") }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                    notifyChar = c
                    peripheral.setNotifyValue(true, for: c)
                }
                if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                    // 알림 캐릭터리스틱과 같을 수도, 다를 수도 있음
                    if writeChar == nil { writeChar = c }
                }
            }
            // 준비되면 세션 시작 (한 번만)
            if writeChar != nil, notifyChar != nil, phase == .connecting {
                Task { await runSession() }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value, let s = String(data: data, encoding: .ascii) else { return }
            buffer += s
            if buffer.contains(">") { resumePending(with: buffer) }
        }
    }
}
