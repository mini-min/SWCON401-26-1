# Sound Box

AirPods 헤드 트래킹 기반 거북목 감지. 자세가 나빠지면 화면 엣지가 빛나고 Dynamic Island가 확장됨.

---

## 빠른 시작 (5단계)

### 1. 압축 해제 후 Xcode에서 열기
```
SoundBox.xcodeproj
```
더블클릭하면 Xcode가 열립니다.

### 2. Signing 설정
Xcode → 좌측 파일 트리에서 `SoundBox` 프로젝트 클릭
→ `Signing & Capabilities` 탭
→ Team: **본인 Apple ID** 선택
→ Bundle Identifier: `com.soundbox.app` (그대로 두거나 고유값으로 변경)

### 3. App Sandbox 비활성화 (중요!)
`Signing & Capabilities` 탭에서
`App Sandbox` capability 옆 **[-] 버튼으로 제거**

> EdgeGlowWindow가 `.screenSaver` 레벨로 모든 앱 위에 떠야 하는데,
> 샌드박스 환경에서는 이 레벨 설정이 무시됩니다.

### 4. macOS Deployment Target 확인
`General` 탭 → Minimum Deployments → **macOS 14.0**

### 5. 빌드 & 실행
`Cmd+R` 또는 ▶ 버튼

---

## AirPods 없이 테스트

AirPods이 없으면 자동으로 **시뮬레이션 모드**로 전환됩니다.
약 20초 주기로 정자세 → 거북목(38°) → 회복을 반복합니다.

화면 엣지 글로우 색상 변화:
- 초록 = 정자세
- 노랑 = 약간 기울어짐  
- 주황 = 자세 교정 필요
- 빨강 = 거북목 (하단 엣지 강하게 빛남)

노치(Dynamic Island) 크기 변화:
- 80pt 작은 점 = 정자세
- 160–256pt 확장 = 경고/거북목 + 각도 표시

---

## 프로젝트 구조

| 파일 | 역할 |
|------|------|
| `SoundBoxApp.swift` | @main, AppDelegate, 두 NSPanel 생성 |
| `HeadTrackingEngine.swift` | CMHeadphoneMotionManager (AirPods IMU) + 시뮬레이션 |
| `EdgeGlowWindow.swift` | 전체화면 투명 NSPanel + CAGradientLayer 엣지 글로우 |
| `IslandWindow.swift` | 노치 위치 Dynamic Island pill (SwiftUI + NSPanel) |
| `SpatialAudioEngine.swift` | AVAudioEnvironmentNode 3D 공간음향 |
| `SettingsView.swift` | 설정 창 (상태/오디오/디스플레이) |

---

## 공간음향 방향 매핑

```
pitch +45° (거북목) → 음원이 뒤+위로 이동  (x=0, y=+0.3, z=+1)
yaw   +30° (오른쪽 회전) → 음원이 왼쪽으로 (x=-1.2, y=0, z=-0.5)
정자세 → 음원이 정면     (x=0, y=0, z=-1)
```

소리가 이상하게 들리는 순간 → 자세를 바로잡으면 → 소리가 정면으로 돌아옴
