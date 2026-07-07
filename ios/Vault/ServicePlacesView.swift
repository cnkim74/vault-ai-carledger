import SwiftUI
import CoreLocation

/// 단골 센터(정비소·카센터·서비스센터 등) 관리 — 전화·길찾기(구글/티맵/카카오).
struct ServicePlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    @State private var editing: ServicePlace?
    @State private var showAdd = false
    @State private var navTarget: ServicePlace?

    var body: some View {
        NavigationStack {
            Group {
                if store.places.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.places) { place in
                                row(place)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("단골 센터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdd) { PlaceEditSheet(store: store, editing: nil) }
        .sheet(item: $editing) { PlaceEditSheet(store: store, editing: $0) }
        .confirmationDialog("어떤 지도로 안내할까요?",
                            isPresented: Binding(get: { navTarget != nil }, set: { if !$0 { navTarget = nil } }),
                            titleVisibility: .visible) {
            ForEach(MapApp.allCases) { app in
                Button(app.label) {
                    if let p = navTarget {
                        PlaceLauncher.route(name: p.name, address: p.address, lat: p.latitude, lng: p.longitude, app: app)
                    }
                    navTarget = nil
                }
            }
            Button("취소", role: .cancel) { navTarget = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 30)).foregroundStyle(Theme.muted)
            Text("등록된 센터가 없어요").font(pd(13)).foregroundStyle(Theme.muted)
            Button { showAdd = true } label: {
                Text("센터 추가").font(pd(13, .semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.goldGradient).clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ p: ServicePlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { editing = p } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.14)).frame(width: 38, height: 38)
                        .overlay(Image(systemName: p.placeCategory.icon).font(.system(size: 15)).foregroundStyle(Theme.gold))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(p.name).font(pd(14, .semibold))
                            Text(p.placeCategory.label).font(pd(9, .bold)).foregroundStyle(Theme.silver)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .overlay(Capsule().stroke(Theme.silver.opacity(0.4), lineWidth: 1))
                        }
                        if let a = p.address, !a.isEmpty {
                            Text(a).font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        if let m = p.memo, !m.isEmpty {
                            Text(m).font(pd(10)).foregroundStyle(Theme.muted2).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                if let phone = p.phone, !phone.isEmpty {
                    actionButton("전화", "phone.fill") { PlaceLauncher.call(phone) }
                }
                actionButton("길찾기", "location.north.fill") { navTarget = p }
            }
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(pd(12, .semibold))
            }
            .foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 센터 추가/수정 시트
struct PlaceEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    let editing: ServicePlace?

    @State private var name: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var phone: String
    @State private var memo: String
    @State private var saving = false
    @State private var showDelete = false

    init(store: VaultStore, editing: ServicePlace?) {
        self.store = store
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _category = State(initialValue: editing?.placeCategory ?? .garage)
        _address = State(initialValue: editing?.address ?? "")
        _phone = State(initialValue: editing?.phone ?? "")
        _memo = State(initialValue: editing?.memo ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("정보") {
                    TextField("이름 (예: 강남 테슬라 서비스센터)", text: $name)
                    Picker("종류", selection: $category) {
                        ForEach(PlaceCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("주소", text: $address)
                    TextField("전화번호", text: $phone).keyboardType(.phonePad)
                    TextField("메모 (선택)", text: $memo)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: {
                            HStack { Spacer(); Text("센터 삭제"); Spacer() }
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "센터 추가" : "센터 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else { Button("저장") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .confirmationDialog("이 센터를 삭제할까요?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("센터 삭제", role: .destructive) { Task { await remove() } }
            Button("취소", role: .cancel) {}
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        var up = VaultStore.PlaceUpsert(
            name: name, category: category.rawValue,
            address: address.isEmpty ? nil : address,
            phone: phone.isEmpty ? nil : phone,
            memo: memo.isEmpty ? nil : memo
        )
        // 주소 → 좌표 지오코딩 (실패해도 저장은 진행, 길찾기는 주소 검색으로 폴백)
        if !address.isEmpty, address != editing?.address, let c = await geocode(address) {
            up.latitude = c.latitude
            up.longitude = c.longitude
        } else if address == editing?.address {
            up.latitude = editing?.latitude
            up.longitude = editing?.longitude
        }
        do {
            if let editing { try await store.updatePlace(id: editing.id, up) }
            else { try await store.addPlace(up) }
            dismiss()
        } catch { /* 무시: 상단 재시도 */ }
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let placemarks = try? await CLGeocoder().geocodeAddressString(address)
        return placemarks?.first?.location?.coordinate
    }

    private func remove() async {
        guard let editing else { return }
        try? await store.deletePlace(id: editing.id)
        dismiss()
    }
}
