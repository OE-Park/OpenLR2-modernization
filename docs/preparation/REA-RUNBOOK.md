# 로컬 REA 분석 준비와 재개 절차

이 문서는 저장소 `reference_repos/rea`의 `443d0778be5922b6ef0e522805ac4002da5edf19`에서 읽은 CLI·provider 문서를 기준으로 한다.
단계 A의 PE import 분석은 실행했다. 단계 B의 Ghidra 복원·함수 분석은 **실행 예정**이다. 실제 요약은 [rea-summary.json](evidence/rea-summary.json)에 있다.

## 현재 사전점검

- 초기 기본 Node 24.18.1은 요구 범위 밖이었고 runtime missing 상태였다.
- `.local/toolchain/`에 Node 24.22.1을 격리 설치했다. 기본 Node·전역 MCP 설정은 바꾸지 않았다.
- REA에서 `npm ci`, `npm run build:cached` 성공. REA CLI 6.8.0, build tasks 3/3 성공. REA 추적 소스 변경 없음.
- `doctor --client codex --json`: Node healthy, Codex 등록 config_drift로 exit 1. GHIDRA_INSTALL_DIR 미설정. CLI PE parser는 두 원본에서 성공했다.
- 활성 REA MCP 연결은 확인하지 않았다. 로컬 CLI로 진행하므로 MCP 등록은 필수 조건이 아니다.
- `/Applications`, `/opt/homebrew/opt`, `~/Applications` 범위 탐색으로 Ghidra 분석 실행기를 찾지 못했다. 다른 경로의 설치 여부는 미확인이다.

## 재실행 환경

OpenLR2 루트에서 실행한다. 프로젝트 로컬 Node를 사용해 기존 기본 런타임과 분리한다.
REA 소스의 `AGENTS.md`와 `.agents/skills/reverse-engineer-anything/SKILL.md`를 따른다.

```sh
REA_ROOT="$PWD/../../reference_repos/rea"
NODE="$PWD/.local/toolchain/node_modules/node/bin/node"
export PATH="$(dirname "$NODE"):$PATH"
"$NODE" --version
"$NODE" "$REA_ROOT/scripts/rea.mjs" --version
"$NODE" "$REA_ROOT/scripts/rea.mjs" doctor --client codex --json
```

의존성을 재설치하거나 REA 소스를 갱신할 때는 해당 소스의 package.json·lockfile·.nvmrc를 다시 확인한다.
이번 설치/빌드는 위 PATH와 `HUSKY=0`을 사용했고, 기존 npm 11.16.0의 CLI를 격리 Node로 실행했다.
소스 CLI는 MCP 등록 없이 분석할 수 있다. 등록이 필요하면 REA dry-run을 검토한 뒤 별도 적용한다.

## 단계 A: 원본 정적 증거

이번 실행에서 PE import뿐 아니라 GAR·ZIP에 `inspect-artifact --detail summary --evidence_output ... --json`을 실행해 archive Evidence를 보존했다.
두 명령 exit 0이다. 아카이브 inventory는 ZIP entry 정적 범위이며 Ghidra DB 의미나 프로그램 동작의 분석이 아니다.

OpenLR2 루트에서 실행한다. stderr, exit code, REA 버전·커밋, 대상 SHA-256을 JSON 옆에 기록한다.
출력 경로는 새 디렉터리로 잡고 원본 바이너리는 실행하지 않는다.

```sh
REA_ROOT="$PWD/../../reference_repos/rea"
NODE="$PWD/.local/toolchain/node_modules/node/bin/node"
mkdir -p .local/evidence/rea-baseline
"$NODE" "$REA_ROOT/scripts/rea.mjs" inspect-pe-imports \
  "$PWD/.local/reference/LR2beta3/LR2body.exe" --json \
  > .local/evidence/rea-baseline/lr2body-imports.json
"$NODE" "$REA_ROOT/scripts/rea.mjs" inspect-pe-imports \
  "$PWD/.local/reference/LR2beta3/LR2.exe" --json \
  > .local/evidence/rea-baseline/launcher-imports.json
```

이 단계의 PE import 조회는 Ghidra가 필요 없는 정적 경로다. 이번 두 결과는 exit 0·coverage complete였다. 범위는 선언된 import table이며 함수 동작·런타임 의존성은 별도다.
질문: 원본의 그래픽·오디오·입력·타이머·파일·플러그인 import 경계는 무엇이며 현재 포크에서 무엇이 바뀌었는가?
import에 없다는 사실만으로 동적 로딩까지 없다고 결론 내리지 않는다.

## 단계 B: Ghidra 프로젝트 재사용

1. `.local/inputs/OpenLR2_2026_06_27_small.gar` 사본을 Ghidra로 새 `.local/ghidra/` 위치에 복원한다. 원본 GAR를 수정하지 않는다.
2. Ghidra 버전, 복원 로그, `.gpr/.rep` 쌍, 실제 root 프로그램 이름을 확인한다.
3. `LR2body.exe.1.1`의 recorded import SHA-256을 [명세](evidence/input-inventory.json)의 ZIP 원본 LR2body.exe 해시와 비교한다. 이름 차이를 임의로 삭제하지 않는다.
4. 일치하면 다음 설정으로 재사용한다. 불일치하면 GAR는 별도 버전 자료로 남기고 ZIP 원본을 새 ephemeral 프로젝트로 분석한다.

```sh
export REA_ANALYSIS_PROVIDER=ghidra
export REA_GHIDRA_PROJECT_PATH="$PWD/.local/ghidra/OpenLR2.gpr"
export REA_GHIDRA_PROGRAM_NAME=LR2body.exe.1.1
# 위 경로는 예시다. 실제 복원 위치·digest 검증 후 실행
"$NODE" "$REA_ROOT/scripts/rea.mjs" analyze \
  "$PWD/.local/reference/LR2beta3/LR2body.exe" --provider ghidra --json \
  > .local/evidence/rea-baseline/lr2body-analysis.json
```

REA는 선택된 `.gpr/.rep`를 소유 임시 위치에 복사해 read-only 처리하고 import digest를 확인하는 경로를 제공한다.
기존 주석·함수명은 사용자 프로젝트의 과거 분석 상태다. 새 REA 발견과 구분한다.
프로그램 수동 패치, 원본 DB 저장, 보호 우회는 이번 준비 범위가 아니다.

## 단계 C: 비교 질문과 증거 원장

각 질문마다 대상 SHA-256, 주소/심볼, 소스 파일, Evidence ID, 관찰/도출/가설/미확인을 적는다.

| 질문 | 원본과 포크에서 비교할 경계 | 아직 필요한 증거 |
|---|---|---|
| 스킨 메모리 소유권 | 목록 초기화·확장·로딩·프리뷰·종료 | 선택 함수 분석 + Windows 반복 할당 스택 |
| 오디오 자원 | keysound/preview/BGA 생성·취소·해제 | 함수 분석 + 실제 live object 추적 |
| 해상도 | graph mode·전역 설정·스킨 좌표·resize | 원본 함수 + 포크 소스 + 실제 4K 캡처 |
| 이식 경계 | 입력·시계·파일·DLL 로딩 | import/호출 경로 + ARM64 실기기 검증 |

분석 전체 함수를 무차별 decompile하지 않는다. 관련 함수만 조사하고 비교용 목록/Evidence는 세션 종료 전에 보존한다.
CLI 옵션이 로컬 문서와 다르면 빌드된 CLI help와 실제 스키마를 우선한다.
