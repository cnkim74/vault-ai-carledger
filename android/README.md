# Wheelet — Android (Kotlin + Jetpack Compose)

iOS(SwiftUI) 앱과 **같은 Supabase 백엔드**를 공유하는 네이티브 안드로이드 앱.
백엔드(DB·RLS·Edge Functions)는 저장소 루트 `../supabase/` 에서 공통 관리한다.

## 열기 / 실행
1. **Android Studio**(최신, Koala/Ladybug 이상)로 **이 `android/` 폴더**를 연다.
2. Gradle Sync가 자동 실행된다. (JDK 17 필요 — Android Studio 내장 JDK 사용 권장)
3. 처음 열면 Gradle Wrapper가 없다고 하면 Android Studio가 생성/다운로드한다.
   (또는 터미널에서 `gradle wrapper` 실행)
4. 에뮬레이터 또는 실기기 선택 후 ▶ Run.

## 구조
```
app/src/main/java/com/cnkim74/wheelet/
├─ MainActivity.kt            앱 진입점(Compose)
├─ ui/theme/Theme.kt          다크+골드 테마(iOS와 동일 톤)
├─ ui/home/HomeScreen.kt      홈 화면(콕핏 기초)
├─ ui/home/HomeViewModel.kt   상태/로드
└─ data/
   ├─ Config.kt               Supabase URL + anon 키(공개 안전)
   ├─ Models.kt               Vehicle / VaultRecord (+ 목업 폴백)
   └─ VaultRepository.kt      PostgREST 조회 (Ktor)
```

## 현재 범위 (스캐폴딩)
- ✅ Supabase에서 차량/기록 조회 → 홈에 표시 (네트워크 실패 시 목업)
- ⬜ 기록 추가/수정, 통계, 차고, Fleet, 프리미엄(Play Billing) 등은 순차 이식 예정

## 참고
- `applicationId` = `com.cnkim74.wheelet` (iOS 번들 `com.cnkim74.vault`와 별개)
- 결제는 iOS의 StoreKit이 아니라 **Google Play Billing**으로 별도 구현한다.
- anon 키는 게시 가능(publishable) 키로, RLS로 데이터가 보호되어 공개돼도 안전하다.
