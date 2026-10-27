# OpenLR2 프로젝트 상태

기준일: 2026-10-27 (Asia/Seoul). **프로젝트 준비 자료 작성, 엔진 개선 미착수.**

## 목표와 우선순위

사용자 목표는 Windows 11 x64·Windows on ARM·macOS arm64 완전 지원, 메모리 누수 감소, 4K 지원이다.
사용자는 기존 LR2 호환을 우선하고 Windows x64 기준을 확보한 다음 ARM64·macOS 백엔드를 분리하는 방향을 선택했다.
지원 완료는 [인수 기준](docs/preparation/ACCEPTANCE.md)의 플랫폼별 실측 결과로 판단한다.

## 작업 기준

| 항목 | 값 |
|---|---|
| 포크 | https://github.com/OE-Park/OpenLR2.git |
| 로컬 | 작업자 로컬 클론 |
| 작업 브랜치 | `prep/platform-modernization` |
| 조사한 소스 HEAD | `521df1396a8fa4550fc31b74e8a8de859342bcc0` |
| 복제 | shallow (`--depth 1`), blob filter. 과거 이력 조사는 별도 fetch 필요 |
| 초기 미커밋 변경 | 없음 |
| REA | 별도 로컬 클론, `main`, `443d0778be5922b6ef0e522805ac4002da5edf19`, 초기 변경 없음 |

## 준비한 것

- 원본 아카이브 2개의 SHA-256·ZIP CRC·멤버 수와 PE 헤더 조사: [입력 명세](docs/preparation/evidence/input-inventory.json).
- `.local/reference/LR2beta3/`에 LR2.exe·LR2body.exe·fmodex.dll만 추출. 플레이 가능한 설치본이 아니며 실행하지 않았다.
- `.local/inputs/`에 Ghidra `.gar` 사본 보존. Ghidra 복원·변환은 하지 않았다.
- REA 6.8.0 로컬 빌드와 원본 PE import 분석: [증거 요약](docs/preparation/evidence/rea-summary.json).
- REA로 GAR·ZIP 아카이브 정적 inventory 실행·Evidence 보존. Ghidra DB 복원·함수 분석과 구분.
- 소스 근거, 플랫폼 제약, 메모리 우선 조사 대상: [현황 조사](docs/preparation/BASELINE.md).
- [설계 초안](docs/superpowers/specs/2026-10-27-platform-modernization-design.md), [작업 순서](docs/preparation/ROADMAP.md), [실행 검증 기준](docs/preparation/ACCEPTANCE.md), [REA 절차](docs/preparation/REA-RUNBOOK.md).
- 원본·분석 DB·개인 데이터가 올라가지 않도록 `/.local/` Git 제외.
- (2026-10-27 추가) upstream 브랜치 `LR2Beta3-v100201`이 원본 디컴파일 소스+주소 CSV임을 확인하고 Ghidra 앞 단계로 편입: [REA 절차 단계 0](docs/preparation/REA-RUNBOOK.md). 스킨 목록 malloc/realloc 구조가 원본 그대로임을 소스 비교로 확인: [현황 조사](docs/preparation/BASELINE.md).
- (2026-10-27 추가) Windows ARM64 정적 감사: [ARM64-AUDIT](docs/preparation/ARM64-AUDIT.md). DxLib 컴파일 장애는 `DxWindow.cpp` 한 블록, 빌드 장애는 CMake 포인터 분기와 ARM64 FMOD 부재.
- (2026-10-27 추가) `LR2_100201.zip`의 MD5·SHA1·SHA-256·크기가 Mac 사본과 Windows 쪽 해시 출력에서 일치. Windows 11 x64 기준 빌드 머신은 별도 데스크톱(SSH 준비 중).

## 실제 검증과 남은 것

| 범위 | 결과 |
|---|---|
| Git 경로·브랜치·HEAD·초기 상태 | 확인 |
| 아카이브 2개 CRC 검사 | 불량 멤버 없음 |
| 원본 PE 및 FMOD DLL 아키텍처 | 원본 x86, vendored bin64 x64, bin86 x86 |
| 해상도·메모리·플랫폼 경로 | 소스 정적 조사. 실제 실행 결과 아님 |
| REA CLI | 초기 runtime missing 해소. 의존성 설치·빌드 성공, 6.8.0 실행 |
| REA 런타임 | `.local/toolchain/`에 Node 24.22.1 격리 설치. 기존 기본 Node 24.18.1 변경 없음 |
| REA 원본 PE 분석 | LR2body.exe: DLL 14개/일반 import 370개, LR2.exe: DLL 17개/일반 import 370개/지연 import 함수 2개. 두 결과 coverage complete |
| REA doctor | exit 1: Codex 등록 config_drift, Ghidra 미설정. CLI PE 분석 성공과 구분 |
| upstream 원본 소스 브랜치 ↔ ZIP 바이너리 | CSV 주소 범위가 `.text` 안, PE 타임스탬프 2010-02-01. 정황 일치, 바이트 동일성은 미검증 |
| Windows ARM64 정적 감사 | DxLib·CMake·런타임 DLL 소스 조사 완료. 빌드·실행 미실행 |
| Ghidra 복원·프로그램 digest 일치 | 미검증 |
| Windows x64 빌드·원본 비교 | 미실행 |
| Windows ARM64 네이티브 빌드·입력·오디오 | 미실행 |
| macOS arm64 빌드·입력·오디오 | 미실행 |
| 누수량·수정·반복 측정 | 미실행 |
| 실제 4K 화면·DPI·프레임 시간 | 미실행 |

## 다음 행동

1. 설계 초안 검토 후 구현 계획 확정. 방향 선택은 받았으나 상세 설계 승인은 아직 없다.
2. Ghidra 설치 위치 지정 후 GAR 복원·원본 digest 비교. REA CLI PE 분석은 이미 가능하며 전역 MCP 설정 변경은 필수 조건이 아니다.
3. Windows x64에서 원본·포크 기준 빌드와 비개인 합성 자료 검증. 누수·프레임·입력 지연 기준값 확보.
4. 메모리 소유권과 해상도 처리의 작은 독립 변경부터 구현. ARM64·macOS 의존성 탐색을 별도 선행 작업으로 진행.

준비 자료는 로컬 작업 브랜치에서 관리한다. 원격 푸시·PR은 실행하지 않았다.
