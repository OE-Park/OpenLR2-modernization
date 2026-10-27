# 구현 전 작업 순서

상세 구현 계획이 아니라 준비 백로그다. 설계 승인 후 파일·테스트 단위 계획으로 구체화한다.
현재 단계별 엔진 작업은 실행하지 않았다. ENV-01, RE-01의 PE import 부분, ARM-01의 정적·문서 조사 부분만 완료했다.
빌드 툴체인은 Visual Studio 2026 Community(v145)를 기준으로 한다(2026-10-27 사용자 결정, VS 2022 라이선스 없음). CI는 GitHub 호스트 러너의 VS 2022를 그대로 쓴다.

| 단계 / 작업 ID | 작업 | 선행 조건 | 완료 근거 |
|---|---|---|---|
| P0 / ENV-01 | REA 호환 Node·의존성·런타임 빌드, CLI 확인 | 현재 runtime missing 해소 | 완료: Node 24.22.1, REA 6.8.0, build 3/3. doctor 등록/provider 문제는 분리 기록 |
| P0 / RE-01 | ZIP 바이너리 PE imports 및 GAR 복원·digest 비교 | ENV-01, Ghidra | 대상별 Evidence ID·hash. 불일치는 명시적으로 분리 |
| P0 / WIN-01 | clean Windows 11 x64에서 `windows-vs2026-x64` preset 기준 빌드 | VS 2026 Community·CMake 4.2+·vcpkg, 소스 기준 고정 | configure/build 로그·exe/DLL machine 검사·기동. 실행 스크립트 [scripts/win01-baseline.ps1](scripts/README.md). 2026-10-27 WIN-DESKTOP에서 configure/build·PE(x64) 검사·추출·스테이징 통과. 런처로 플레이어 등록 후 콘솔 세션에서 타이틀 화면 도달·Esc 정상 종료(exit 0) 확인 |
| P0 / QA-01 | 합성 chart/skin·빈 DB로 원본/포크 기준 시나리오 확보 | WIN-01 | 판정·리플레이·DB·입력·오디오 baseline. 생성기 [qa/](qa/README.md) 작성(2026-10-27, 엔진 로드 전) |
| P1 / MEM-01 | 스킨 목록/CSTR 소유권 진단·최소 회귀 테스트 | QA-01 | allocation stack·같은 입력의 실패 재현 |
| P1 / MEM-02 | 스킨 목록 소유권 수정 | MEM-01 | 이전 실패→수정 후 통과·같은 프로파일 반복 측정 |
| P1 / MEM-03 | sound/graph/BGA 취소·재시작·종료 수명 감사 | QA-01 | 자원 카운터·누수 stack·해제 후 callback 검사 |
| P1 / UHD-01 | 4K 전역/스킨 매핑·입력 검증·크기 경계 테스트 | QA-01 | 해상도 테이블 테스트·잘못된 스킨 처리 |
| P1 / UHD-02 | 4K 렌더·DPI·resize·Alt+Tab·VRAM 회귀 검증 | UHD-01, MEM-02 | 실제 framebuffer 캡처·프레임 시간·반복 자원 수 |
| P2 / PORT-01 | 백엔드 경계 설계 spike: 창/그리기/오디오/HID/파일/시계 | 설계 승인, QA-01 | 최소 1곡 흐름과 호환 차이 목록 |
| P3 / MAC-01 | macOS arm64 창/렌더/오디오/입력/파일 구현. IR(LR2IR·CustomIR) 제거 빌드 | PORT-01, 의존성 결정, IR-01 | arm64 Mach-O·실제 곡/BGA/장치 테스트. 산출물에 IR 코드·모듈 로드 경로가 없음을 확인 |
| P3 / MAC-02 | app bundle·서명·깨끗한 계정 설치·첫 실행 검증 | MAC-01 | 패키지·서명 검증·cold/warm 로그 |
| P1 / ASIO-01 | Windows ASIO 출력 검증: 기존 `output=2` 경로·드라이버 열거·버퍼/지연 측정·실패 폴백 | QA-01, 실기기 ASIO 장치 | 장치별 지연·드롭 측정, 설정→실행 경로 기록. macOS는 명시 미지원 |
| P1 / I18N-01 | 다국어 범위 명세: 파일명·메타·IME·폰트·메시지·DB 해시 호환. `932` 고정 37곳 분류 | QA-01 | 언어별 합성 자료(일·한·영·공백·긴 경로)로 선곡·플레이·DB 재조회 통과 |
| P2 / IR-01 | IR 제외 조건 명세: 빌드 옵션으로 레거시 LR2IR·CustomIR·랭킹 표시를 빼는 경계, 기준 오디오 환경 정의, ARM64 허용 여부 | PORT-01 | 옵션 on/off 빌드 비교, off 빌드에서 네트워크 송신·모듈 로드 없음 확인. 2026-10-27 결정: macOS 빌드는 IR 제거. CustomIR 전송이 원본 long sound(60초 초과)·0 note 거부를 건너뛰는 공백 처리([ECOSYSTEM-SOURCES 9.2](ECOSYSTEM-SOURCES.md)) |
| P2 / LAUNCH-01 | 런처 설계: LR2Nexus 기능·설정 스키마 조사, 형태·언어·라이선스 결정(ADR) | 설계 승인, 라이선스 결정 | ADR + 기능 목록. GPL-3.0 코드 반입 여부를 명시 |
| P4 / REL-01 | 플랫폼별 CI 빌드·재현 패키지·실기기 체크 연결 | 각 플랫폼 빌드 성립 | 아키텍처별 산출물 + 수동 검증 기록 |
| P5 / ARM-01 | ARM64 FMOD/대체 오디오·DxLib/대체 렌더·plugin 의존성 검증 | PORT-01 | 의존성별 네이티브 빌드·license/provenance 목록. 정적·문서 조사 부분은 2026-10-27 완료: [ARM64-AUDIT](ARM64-AUDIT.md). FMOD·vcpkg·MSVC는 비장애, DxLib은 공식 ARM64/macOS 없음 |
| P5 / ARM-02 | Windows ARM64 configure/build·네이티브 실기기 검증 | ARM-01 | PE ARM64 exe와 로드 DLL 검사·인수 시나리오 |

Windows x64의 호환 기준을 먼저 확보한다. 의존성 조사 자체는 일찍 수행해 ARM64/macOS의 큰 제약을 미리 밝힌다.
Windows ARM64 구현(ARM-01 나머지·ARM-02)은 2026-10-27 사용자 결정으로 가장 후순위(P5)다. 정적 감사 결과는 [ARM64-AUDIT](ARM64-AUDIT.md)에 보존하고 다른 작업의 선행 조건으로 삼지 않는다.
기존 Windows backend를 한 번에 제거하지 않는다. 새 경계에서 기존 backend와 새 backend를 교체하며 비교한다.
SDK/백엔드 교체로 판단 결과가 바뀌면 별도 호환 문제로 추적한다.

## 바로 이어갈 첫 구현 후보

1. 재현 가능한 스킨 목록 소유권 테스트와 최소 수정.
2. `GetConfigResolution`과 스킨 해상도 파서의 단일 명세·4K 전역 값·잘못된 입력 검증.

둘 다 Windows x64 기준 확보 이후 수행한다. 후보 선정은 구현 완료·설계 전체 승인과 다르다.
