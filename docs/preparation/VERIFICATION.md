# 준비 세션 검증 기록

2026-10-27, macOS arm64 호스트. 소스 조사 기준 HEAD `521df1396a8fa4550fc31b74e8a8de859342bcc0`.

| 검증 | 실행 결과 | 증명하는 범위 |
|---|---|---|
| Git 경로/브랜치/HEAD/status/worktree | 초기 clean, `prep/platform-modernization` 생성 | 대상 식별, 기존 변경 없음 |
| Python zipfile.testzip | 입력 아카이브 2개 불량 멤버 없음 | ZIP CRC, 실행 호환성은 미검증 |
| SHA-256 재검사 | Downloads 원본 2개가 명세와 일치 | 입력 바이트 식별 |
| PE header 정적 조사 | 원본 x86, FMOD bin64 x64/bin86 x86 | machine/optional header, 실제 로드는 미검증 |
| REA 의존성 설치 | npm ci exit 0 | 고정 lockfile 설치. npm audit moderate 1개 보고, 자동 수정 안 함 |
| REA build:cached | exit 0, tasks 3/3 successful | REA 6.8.0 CLI·skill 산출물 빌드, 전체 REA 테스트 실행은 아님 |
| REA --version | exit 0, 6.8.0 | 프로젝트 격리 Node 24.22.1에서 CLI 실행 |
| REA doctor --client codex --json | exit 1 | Node healthy, Codex config_drift, Ghidra 미설정. CLI 정적 분석 성공과 구분 |
| REA inspect-pe-imports ×2 | exit 0, complete, issues 0 | 원본의 선언된 PE 일반/지연 import 분석 |
| REA inspect-artifact ×2 | exit 0, summary Evidence와 bundle 보존 | GAR/ZIP의 bounded 정적 inventory. DB 복원은 아님 |
| cmake --list-presets (macOS) | exit 0, 출력 preset 없음 | Windows host 조건이 있는 preset 열거. configure/build는 아님 |
| 문서 상대 링크·JSON 검사 | 링크 대상 존재·JSON 파싱·hash 일치 확인 | 준비 자료 내부 일관성 |
| git diff --check | exit 0 | 추적 변경 공백 오류 검사 |
| git check-ignore | local GAR/EXE/Node 경로 제외 확인 | 개인 자료·도구 산출물 Git 제외 |
| builder check | 중요 누락 없음 | 설계 계획 가능성 검토. 제품 검증은 아님 |
| REA git status | 추적 변경 없음 | 참조 저장소 소스 보존 |

REA 실제 명령/exit code/stdout/stderr는 `/.local/evidence/rea-baseline/commands.json`과 같은 폴더에 있다.
공유 가능한 digest·Evidence ID·coverage는 [rea-summary.json](evidence/rea-summary.json)에 있다.

미실행: OpenLR2 Windows x64/ARM64/macOS arm64 빌드와 실행, GAR 복원·program digest 비교,
함수 decompile, 누수 실측/수정, 실제 4K·DPI·입력·오디오·BGA·프레임 시간 검사.
이 세션은 준비 자료와 분석 도구를 마련했으며 플랫폼 지원 기능을 구현하지 않았다.
