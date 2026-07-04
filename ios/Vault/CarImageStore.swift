import UIKit

/// 차량 사진 저장/로드 — 차량별로 Documents/car-photo-<id>.jpg에 영속화.
/// 샘플 이미지는 번들의 SampleCars/*.png.
enum CarImageStore {
    static let sampleNames = ["car-red", "car-blue", "car-sky"]

    private static func fileURL(for vehicleID: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("car-photo-\(vehicleID.uuidString.lowercased()).jpg")
    }

    static func load(for vehicleID: UUID) -> UIImage? {
        UIImage(contentsOfFile: fileURL(for: vehicleID).path)
    }

    static func save(_ image: UIImage, for vehicleID: UUID) {
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: fileURL(for: vehicleID))
        }
    }

    static func clear(for vehicleID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: vehicleID))
    }

    static func sample(_ name: String) -> UIImage? {
        if let img = UIImage(named: name) { return img }
        // 동기화 그룹이 폴더 구조를 유지한 경우 대비
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "SampleCars"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }
}
