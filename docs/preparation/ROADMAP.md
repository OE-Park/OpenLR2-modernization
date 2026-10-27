# 구현 전 작업 순서

상세 구현 계획이 아니라 준비 백로그다. 설계 승인 후 파일·테스트 단위 계획으로 구체화한다.
현재 단계별 엔진 작업은 실행하지 않았다. ENV-01과 RE-01의 PE import 부분만 완료했다.

| 단계 / 작업 ID | 작업 | 선행 조건 | 완료 근거 |
|---|---|---|---|
| P0 / ENV-01 | REA 호환 Node·의존성·런타임 빌드, CLI 확인 | 현재 runtime missing 해소 | 완료: Node 24.22.1, REA 6.8.0, build 3/3. doctor 등록/provider 문제는 분리 기록 |
| P0 / RE-01 | ZIP 바이너리 PE imports 및 GAR 복원·digest 비교 | ENV-01, Ghidra | 대상별 Evidence ID·hash. 불일치는 명시적으로 분리 |
| P0 / WIN-01 | clean Windows 11 x64에서 기존 preset 기준 빌드 | VS 2022·vcpkg, 소스 기준 고정 | configure/build 로그·exe/DLL machine 검사·기동 |
| P0 / QA-01 | 합성 chart/skin·빈 DB로 원본/포크 기준 시나리오 확보 | WIN-01 | 판정·리플레이·DB·입력·오디오 baseline |
| P1 / MEM-01 | 스킨 목록/CSTR 소유권 진단·최소 회귀 테스트 | QA-01 | allocation stack·같은 입력의 실패 재현 |
| P1 / MEM-02 | 스킨 목록 소유권 수정 | MEM-01 | 이전 실패→수정 후 통과·같은 프로파일 반복 측정 |
| P1 / MEM-03 | sound/graph/BGA 취소·재시작·종료 수명 감사 | QA-01 | 자원 카운터·누수 stack·해제 후 callback 검사 |
| P1 / UHD-01 | 4K 전역/스킨 매핑·입력 검증·크기 경계 테스트 | QA-01 | 해상도 테이블 테스트·잘못된 스킨 처리 |
| P1 / UHD-02 | 4K 렌더·DPI·resize·Alt+Tab·VRAM 회귀 검증 | UHD-01, MEM-02 | 실제 framebuffer 캡처·프레임 시간·반복 자원 수 |
| P2 / PORT-01 | 백엔드 경계 설계 spike: 창/그리기/오디오/HID/파일/시계 | 설계 승인, QA-01 | 최소 1곡 흐름과 호환 차이 목록 |
| P2 / ARM-01 | ARM64 FMOD/대체 오디오·DxLib/대체 렌더·plugin 의존성 검증 | PORT-01 | 의존성별 네이티브 빌드·license/provenance 목록 |
| P2 / ARM-02 | Windows ARM64 configure/build·네이티브 실기기 검증 | ARM-01 | PE ARM64 exe와 로드 DLL 검사·인수 시나리오 |
| P3 / MAC-01 | macOS arm64 창/렌더/오디오/입력/파일 구현 | PORT-01, 의존성 결정 | arm64 Mach-O·실제 곡/BGA/장치 테스트 |
| P3 / MAC-02 | app bundle·서명·깨끗한 계정 설치·첫 실행 검증 | MAC-01 | 패키지·서명 검증·cold/warm 로그 |
| P4 / REL-01 | 플랫폼별 CI 빌드·재현 패키지·실기기 체크 연결 | 각 플랫폼 빌드 성립 | 아키텍처별 산출물 + 수동 검증 기록 |

Windows x64의 호환 기준을 먼저 확보한다. 의존성 조사 자체는 일찍 수행해 ARM64/macOS의 큰 제약을 미리 밝힌다.
기존 Windows backend를 한 번에 제거하지 않는다. 새 경계에서 기존 backend와 새 backend를 교체하며 비교한다.
SDK/백엔드 교체로 판단 결과가 바뀌면 별도 호환 문제로 추적한다.

## 바로 이어갈 첫 구현 후보

1. 재현 가능한 스킨 목록 소유권 테스트와 최소 수정.
2. `GetConfigResolution`과 스킨 해상도 파서의 단일 명세·4K 전역 값·잘못된 입력 검증.

둘 다 Windows x64 기준 확보 이후 수행한다. 후보 선정은 구현 완료·설계 전체 승인과 다르다.
