# OpenLR2 작업 지침

현재 상태의 원본은 [PROJECT-STATUS.md](PROJECT-STATUS.md)다. 준비 문서의 계획을 구현 완료로 보고하지 않는다.

- 기존 LR2 곡·스킨·판정·리플레이·점수 DB 호환을 우선한다. 플랫폼 이식과 판정 변경을 같은 변경에 섞지 않는다.
- Windows 11 x64, Windows 11 ARM64, macOS arm64는 별도 빌드·실기기 검증 대상이다. 포인터 크기 8만으로 x64를 판정하지 않는다. 에뮬레이션 결과와 네이티브 결과를 구분한다.
- 엔진 구현 전 [설계 초안](docs/superpowers/specs/2026-10-27-platform-modernization-design.md)을 검토한다. 백엔드 선택은 아직 확정하지 않았다.
- `/.local/`은 Git 제외 대상이다. 원본 배포본·Ghidra DB·곡·스킨·개인 점수·실행 로그를 추적하지 않는다. 기존 사용자 플레이 폴더에서 검증하지 않는다.
- REA 사용법은 [분석 절차](docs/preparation/REA-RUNBOOK.md)를 따른다. 원본 바이너리를 실행하지 않는 정적 조사를 먼저 수행한다. Ghidra 프로그램 이름과 바이너리 SHA-256 일치를 검증한다.
- 메모리 수정은 같은 입력의 수정 전후 반복 시나리오와 할당 스택 근거를 남긴다. ASan 통과, RSS 감소, 실제 누수 제거를 서로 대신하는 증거로 쓰지 않는다.
- 4K는 `#RESOLUTION,3`의 기존 처리부터 확인한다. 전역 설정, 화면 전환, 렌더 크기, DPI, 입력 좌표, GPU 자원 수명까지 검증한다.
- 검증 명령·환경·커밋·결과를 기록하고 미실행 항목은 그대로 남긴다. 현재 CI의 x86/x64 빌드가 ARM64·macOS 지원을 증명하지 않는다.

현재 작업은 조사·준비다. `CMakeLists.txt`·CI workflow는 수정하지 않았고(`CMakePresets.json`에 VS 2026 preset만 추가), 세 플랫폼 실행 지원이나 누수 개선을 완료하지 않았다.
제품 코드 변경은 #4(다중 모니터 전체 화면 크래시) 수정 하나다: `LR2/Main.cpp`의 화면 모드 처리와 `dep/DxLib`의 D3D9 어댑터 선택.

## Windows x64 개발

- 기준 툴체인: Visual Studio 2026 Community(C++ 데스크톱 워크로드), VS 내장 CMake(`<VS>\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`, 4.3.1에서 `Visual Studio 18 2026` 생성기 확인), vcpkg 커밋 `cd61e1e2…78e3`(`VCPKG_ROOT`).
- 빌드: `cmake --preset windows-vs2026-x64` → `cmake --build --preset windows-vs2026-x64-relwithdebinfo`. VS GUI는 `out\windows-vs2026-x64\OpenLR2.slnx`를 연다. 처음 한 번은 [scripts/win01-baseline.ps1](docs/preparation/scripts/README.md)이 vcpkg부터 산출물 검사까지 해 준다.
- 실행 파일은 시작할 때 작업 폴더를 exe 위치로 바꾼다(`LR2/Main.cpp` `current_path(GetExecutablePath())`). `LR2files`·`fmod.dll`이 exe 옆에 있어야 한다. 빌드 출력 폴더에서 바로 실행하거나 디버깅하려면 원본 배포본에서 추출한 `LR2files`를 그 폴더에 두고 플레이어 DB를 런처로 만든다.
- 단위 검사: `OpenLR2_x64.exe -test`(`run_tests()`). DxLib 초기화 전에 끝나므로 창이 필요 없다. 다만 위 작업 폴더 조건 때문에 게임 폴더에서 실행한다. 종료 코드 0과 `Log.txt`의 `tests passed`가 통과다.
- SSH·서비스 세션에서 띄운 게임은 디스플레이가 `WinDisc 0x0`이라 화면 검증 근거가 아니다. 화면·전체 화면·모니터 검증은 대화형 세션에서 한다. 오류창은 숨김 창이라 `MainWindowTitle`로는 보이지 않는다.
- 다중 모니터: 게임 창은 시작 순간 마우스 커서가 있는 모니터에 생긴다(`SetUseDisplayIndex(-1)`). `EnumDisplayMonitors` 순서와 Direct3D9 어댑터 순서는 다를 수 있고 프로세스마다 달라질 수 있다. 모니터 관련 수정은 `docs/preparation/qa/windows/d3d9probe.cpp`(PR #3)로 두 순서를 기록하고 모니터마다 시험한다.
- `dep/DxLib`은 DxLib 3.24f에 로컬 수정이 섞인 사본이다. 이 저장소에서 더하는 수정은 `OpenLR2` 주석으로 표시한다.
