# 소스·배포본 현황 조사

조사일 2026-10-27. 소스 기준 `521df1396a8fa4550fc31b74e8a8de859342bcc0`.
관찰, 소스에서 도출한 위험, 아직 측정하지 않은 현상을 구분한다.

## 관찰한 사실

| 근거 | 확인한 내용 | 의미 |
|---|---|---|
| `CMakeLists.txt` | CMake 3.29 이상, C/C++, 앱은 C++23 | 기존 CMake를 빌드 기준 후보로 유지 |
| `CMakePresets.json` | Windows VS 2022 x86/x64와 ASan preset. 2026-10-27 생성기만 바꾼 `windows-vs2026-*` preset 추가(조사 HEAD 이후 변경) | ARM64·Apple preset 없음 |
| `.github/workflows/build.yml` | Windows 2022 x86/x64 빌드·산출물 업로드 | 실행·누수·4K 검증은 없음 |
| `CMakeLists.txt` FMOD 분기 | WIN32·LINUX만 처리, 그 외 fatal error | 현재 구성에 macOS FMOD 경로 없음 |
| `CMakeLists.txt` DxLib 분기 | Windows 소스 또는 Linux OpenAL/EGL/GL/X11 경로 | Linux 경로를 macOS 지원으로 간주할 수 없음 |
| FMOD DLL PE 헤더 | bin64는 x64, bin86는 x86 | 64비트 ARM도 bin64를 고르는 현재 분기로는 ARM64 의존성을 충족하지 못함 |
| `dep/FMOD/fmod_common.h:57` | `FMOD_VERSION 0x00020310` | 원본 배포본의 fmodex.dll과 다른 세대, 대체 가능성은 별도 검증 |
| `OpenLR2.manifest` | Win10/11 호환 선언·UTF-8 code page | 선언이 Windows 11 실행·DPI 검증을 대신하지 않음 |
| `LR2/En_timer.cpp`, `En_input.cpp`, `En_fileutil.cpp`, `Main.cpp`, `LR2_customir.cpp` | Windows 조건부 API와 일부 비Windows 경로 | 타이머·HID/MIDI·파일·플러그인 경계별 이식 조사 필요 |
| 루트 추적 파일 | 최상위 LICENSE를 찾지 못함 | 배포 준비 시 소스·FMOD·DxLib·자산의 허용 범위와 고지 자료 확인 필요. 법적 판정은 하지 않음 |

## 4K는 부분 구현 상태

- `LR2/LR2_skinmanage.cpp:255` 이후 `#RESOLUTION` 처리에서 값 3을 3840×2160으로 변환한다.
- `LR2/LR2_skinload.cpp:1902` 이후 스킨 태그가 있으면 해당 크기로 `Resize`한다.
- `LR2/En_graphic.cpp:21`의 전역 `GetConfigResolution`은 1=1280×720, 2=1920×1080, 나머지=640×480이다. 전역 값 3의 4K 매핑은 없다.
- `new_command(skin).md`에는 이미 `#RESOLUTION,3`이 문서화돼 있다. README의 전역 설정 안내는 0/1/2만 설명한다.
- `Resize`는 `SetGraphMode`, 창 배율, 창 위치, `skinSizeX/Y`를 처리한다. 성공/실패와 실제 framebuffer 크기는 미측정이다.

따라서 작업 이름은 “4K 신규 모드만 추가”가 아니라 “스킨·전역 설정 일관화와 4K 실행 안정화”다.

## 메모리 조사 우선순위

| 대상 | 소스 근거 | 다음 검증 |
|---|---|---|
| `InitSkinData`, `ExpandSkinMax` | `LR2_skinmanage.cpp:176` 이후 malloc/realloc로 SkinHeader·CSTR 배열을 직접 다룸. 누수 FIXME 존재 | CSTR 생성·복사·파괴 의미, 성공·실패·확장·재초기화·종료 수명 추적. 정적 의심과 누수 실측 구분 |
| `SkinManage` | `structure.h:1512`에서 raw Data 포인터, 명시적 소유 destructor 없음 | 다른 정리 경로 유무를 더 조사한 뒤 RAII 전환 범위 결정 |
| `ReleaseSound` | `En_audio.cpp:253` 이후 load·filename 조건의 조기 반환 및 두 백엔드별 해제 | 파일명과 리소스 보유 상태가 분리되는 경우를 재현. 조기 반환만으로 누수 확정하지 않음 |
| 스킨/폰트/이미지 | `LR2_skinload.cpp`에 여러 DeleteGraph 경로 | 로딩 취소·화면 전환·4K resize에서 handle 누적과 중복 해제 추적 |
| BGA·오디오 비동기 작업 | 원본/포크 비교 필요 | 빠른 재시작·다음 곡·취소·종료에서 join/release 순서와 callback 접근 검증 |

4GB 패치·64비트 전환·캐시 제한은 누수 제거를 대신하지 않는다. 현재 소스 조사만으로 누수의 크기·빈도·전체 원인을 확정하지 않았다.

## 로컬 참조 자료

Downloads의 두 파일은 읽기만 수행했다. CRC 결과·정확한 SHA-256·선별 멤버 정보는 [input-inventory.json](evidence/input-inventory.json)에 있다.

- `LR2_100201.zip`: 435개 멤버, 원본 LR2.exe·LR2body.exe·fmodex.dll은 PE x86. DLL·보조 도구가 현대 플랫폼에서 실행 가능하다는 뜻은 아니다.
- `OpenLR2_2026_06_27_small.gar`: 23개 멤버, `OpenLR2.gpr`와 Ghidra DB 데이터 포함. 속성에 `LR2.exe`, **`LR2body.exe.1.1`**, Archive `LR2`가 선언돼 있다.
- `.gar`의 프로그램 이름과 ZIP의 `LR2body.exe` 이름이 다르다. 바이너리 해시 일치를 확인하기 전에는 동일 프로그램·버전으로 취급하지 않는다.
- `.gar` 안의 역슬래시 경로를 일반 unzip으로 풀어 `.gpr/.rep` 복원이라고 보고하지 않는다. Ghidra의 프로젝트 복원 기능을 사용해야 한다.
- 입력 명세는 Python 표준 라이브러리로 만든 정적 조사 자료다. 별도의 [REA 요약](evidence/rea-summary.json)에 실제 PE import Evidence ID가 있다. Ghidra 함수 분석·런타임 관찰은 아직 없다.

## 원본 디컴파일 소스와 포크의 비교 (2026-10-27)

upstream 브랜치 `LR2Beta3-v100201`(원본 디컴파일 소스, 절차는 [REA-RUNBOOK 단계 0](REA-RUNBOOK.md))과 현재 포크를 함수 단위로 비교할 수 있다.

- `InitSkinData`·`ExpandSkinMax`는 원본 `LR2f.cpp:22603,22621`과 포크 `LR2/LR2_skinmanage.cpp:176,195`가 같은 구조다. 원본은 `realloc(..., (Max + 100) * 0xb14)`로 디컴파일 매직 넘버를 그대로 쓰고, 포크는 `sizeof(SkinHeader)`·`assert`·FIXME 주석만 더했다. 스킨 목록의 raw malloc/realloc 소유권은 원본 설계를 그대로 물려받은 것이다.
- `ReleaseSound(AUDIO*, SOUNDDATA*)`도 원본 `LR2f.cpp:28483`과 포크 `LR2/En_audio.cpp:253`에 같은 시그니처로 있다. 조기 반환 조건 비교는 아직 하지 않았다.
- 이 비교는 정적 소스 비교다. 원본 바이너리의 실제 누수량·동작은 측정하지 않았다.

## Windows ARM64 정적 감사 (2026-10-27)

결과는 [ARM64-AUDIT](ARM64-AUDIT.md)에 있다. 요약: DxLib에서 ARM64 컴파일을 막는 코드는 `Windows/DxWindow.cpp`의 `__cpuid`/`__rdtsc` 블록 하나(약 70줄)뿐이고, 나머지 x86 asm 119곳은 `DX_NON_INLINE_ASM`으로 이미 dead code다. 빌드 장애는 CMake의 포인터 크기 분기와 ARM64 FMOD 바이너리 부재다.

## 기존 재발 기록 반영

Projects DevArchive의 vcpkg clean-machine 헤더 누락, FileTracker 접근 거부, BGA 첫 실행 초기화 실패, PHOENIXWAN 재열거 기록을 확인했다.
빌드는 깨끗한 환경과 아키텍처별로 검증하고, BGA는 cold/warm을 나누며, USB 증상은 OS 장치 열거와 앱 입력을 구분한다.
다른 프로젝트의 특정 장치 해결책을 OpenLR2의 검증된 기능으로 복사하지 않는다.

## 실제 REA 분석 결과

REA 6.8.0을 고정 소스에서 빌드했고, 프로젝트 로컬 Node 24.22.1로 두 원본의 `inspect-pe-imports`를 실행했다. 두 명령 exit 0, coverage complete, issues 0이다.

- LR2body.exe: 일반 DLL 14개·import 함수 370개. fmodex.dll 함수 41개, KERNEL32/USER32/GDI32/WINMM·레거시 미디어 API import를 관찰했다.
- LR2.exe: 일반 DLL 17개·import 함수 370개. 지연 DLL OLEACC.dll의 함수 2개를 별도로 관찰했다.
- 두 이미지에 LoadLibrary/GetProcAddress import가 있어 import table에 없는 의존성도 후속 조사해야 한다.
- REA doctor exit 1은 Codex 등록 config_drift를 보고했다. Ghidra도 설정되지 않았다. 이 결과는 CLI PE parser의 사용 불가를 뜻하지 않는다.
- 전체 JSON/명령별 exit code/stderr는 `.local/evidence/rea-baseline/`, 공유 가능한 Evidence ID·digest·coverage 요약은 [rea-summary.json](evidence/rea-summary.json)에 보존했다.

의존성 설치 시 npm audit가 moderate 항목 1개를 보고했다. 설치 lockfile은 변경하지 않았고 audit fix나 REA 소스 수정은 하지 않았다. 분석용 개발 의존성 전체의 보안 감사를 완료한 것은 아니다.
