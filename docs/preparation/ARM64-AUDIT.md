# Windows ARM64 사전 감사 (ARM-01 정적 조사)

조사일 2026-10-27. 소스 기준 `521df1396a8fa4550fc31b74e8a8de859342bcc0`, 브랜치 `prep/platform-modernization`.
정적 소스 조사와 외부 문서 조사만 수행했다. ARM64 빌드·실행은 하지 않았다. 구현 제안이 아니라 범위 확정 자료다.

## 결론

| 항목 | 결과 | 근거 |
|---|---|---|
| DxLib 소스의 ARM64 컴파일 장애 | 파일 1개, 함수 1개, 약 70줄 | `dep/DxLib/Windows/DxWindow.cpp:10076-10138`(`__cpuid` 7회), `:10256-10278`(`__rdtsc` 2회), 매크로 `:126-132` |
| DxLib 나머지 x86 asm | 119곳 전부 이미 dead code | `dep/DxLib/DxCompileConfig.h:45`가 `DX_NON_INLINE_ASM`을 무조건 정의. 모든 asm이 그 `#ifndef` 아래이고 스칼라 폴백이 있다 |
| LR2 소스(`LR2/`) x86 asm·인트린식 | 0 | grep 결과 없음 |
| 빌드 시스템 장애 | CMake가 포인터 8바이트를 x64로 간주해 x64 FMOD를 선택 | `CMakeLists.txt:36-63`. vendored FMOD는 bin64(x64)·bin86(x86)뿐 |
| DxLib에 CPU 계열 분기 | 없음 | `_M_ARM64`·`__aarch64__` 분기 0. 64비트 판별은 `_WIN64`뿐이고 ARM64 MSVC도 `_WIN64`를 정의하므로 자료형·헤더 배관은 그대로 쓸 수 있다 |

## DxLib x86 코드 분류

A = ARM64에서 컴파일 실패, B = 가드 + 스칼라 폴백, C = 가드만 있고 폴백 없음, D = 무해.

| 분류 | 수 | 위치 |
|---|---|---|
| A | 2 영역 | `Windows/DxWindow.cpp` CPU 검사 블록(`:10066-10372`). `DX_NON_INLINE_ASM && _WIN64` 분기가 x86 인트린식 `__cpuid`·`__rdtsc`를 쓴다. `#else`는 x86 인라인 asm이라 폴백이 아니다 |
| B | 119 블록 / 14 파일 | DxBaseFunc.cpp 13, DxBaseFunc.h 2, DxModel.cpp 1, DxArchive_.cpp 1, DxMask.cpp 12, DxBaseImage.cpp 24, DxMemImgDrawFunction0.cpp 48, DxMemImgDrawFunction1.cpp 8, DxMemImgDrawFunction3.cpp 2, DxGraphics.cpp 1, DxUseCLib.cpp 4, Windows/DxModelD3D9.cpp 1, Windows/DxMaskD3D9.cpp 2 |
| C | 0 | |
| D | 호출 규약 키워드 약 2,150개, `_WIN64` 크기 선택 약 90개, `#if 0` RDTSC 타이머, 주석 asm | MSVC ARM64는 `__stdcall`·`__fastcall`을 무시한다 |

A를 고치면 영향받는 소비자: `WinData.UseMMXFlag/UseSSEFlag/UseSSE2Flag`(`DxWindow.h:285-287`)의 사용처 16곳은 전부 `#ifndef DX_NON_INLINE_ASM` 아래라 dead. 공개 `GetUseMMXFlag` 계열(`DxGateway.cpp:1369-1389`)은 FALSE를 돌려주면 된다. `PcInfo.CPUSpeed`·`CPUString`은 0·빈 문자열이 된다.

## DxCompileConfig.h 스위치

- `:45` `DX_NON_INLINE_ASM` 무조건 정의. `:441-445`에서 `_WIN64 || __ANDROID__ || __APPLE__ || DX_GCC_COMPILE`일 때 재정의.
- `:433-437` `PLATFORM_64BIT` = `_WIN64 || __LP64__`.
- 활성 기능 절단: `DX_NON_MODEL`(:144), `DX_NON_BULLET_PHYSICS`(:148), `DX_NON_SHADERCODE_BINARY`(:200, 셰이더를 런타임 텍스트 컴파일 → 셰이더 컴파일러 DLL 필요), `DX_NON_LIVE2D_CUBISM4`(:203).
- `DX_NON_STOPTASKSWITCH`(:258)는 Android/Apple 블록 안이라 Windows에서 비활성.
- CPU 계열 스위치 없음. `DxDataType.h:16-29`는 OS로만 헤더를 고른다.

## Windows 백엔드 런타임 의존성

| 항목 | 관찰 | ARM64 영향 |
|---|---|---|
| D3D9/D3D11 | `LR2/Main.cpp:337` 기본 D3D9, CLI로 D3D11. dxgi/d3d11/d3d9 DLL 동적 로드(`DxGraphicsAPIWin.cpp:1769,1814,4174`) | 세 DLL 모두 ARM64 Windows에 있음 |
| 셰이더 컴파일러 | `DxWinAPI.cpp:1185-1211` d3dx9_50…24.dll 시도 후 `:1204-1232` D3DCompiler_47…33.dll 폴백 | d3dx9_*는 ARM64 빌드가 없다. D3DCompiler_47은 ARM64 Windows에 있다. D3D9 + D3DX 없는 셰이더 경로는 끝까지 추적하지 않음 |
| DirectInput | `CoCreateInstance(CLSID_DIRECTINPUT, IID_IDIRECTINPUT7)`(`DxInputWin.cpp:1841`) → DI8 폴백(`:1869`). 데이터 포맷은 `_WIN64` 크기로 수작업 | 포인터 8바이트 기준이라 ARM64에 맞음. IDirectInput7 CLSID의 ARM64 등록 여부는 미확인 |
| XInput | xinput1_4/1_3/9_1_0 LoadLibrary(`:1801-1810`) | xinput1_4.dll은 ARM64에 있음 |
| X3DAudio | X3DAudio1_0…1_7.dll LoadLibrary(`DxSoundWin.cpp:2268`) | 레거시 DX SDK 재배포본, ARM64 빌드 없음. 로드 실패 시 동작 미조사 |
| 키보드 훅 | `SetWindowsHookExW(WH_KEYBOARD_LL)`(`DxWindow.cpp:5660,11141`) | 이식 가능. `DxKeyHookBinary.cpp`의 x86/x64 DLL 블롭은 `#if 0`이라 미사용 |
| Live2D | `DX_NON_LIVE2D_CUBISM4`로 컴파일 제외 | 해당 없음 |
| 그 외 LoadLibrary | ws2_32, winmm, ole32, Mfplat, Mfreadwrite, XAudio2_8, DSound, msacm32 등 | 전부 ARM64 Windows 기본 제공 |

## 기타 의존성

- `dep/sqlite/sqlite3.c:15598-15602` 바이트 순서 판별에 `_M_ARM64` 포함. 문제 없음.
- `dep/md5`, `dep/tinyxml`: 아키텍처 매크로·asm 없음.
- `dep/dxlib-for-linux`: 패치 파일만 있고 DxLib 소스·`libDxLib.a`·`libfmod.so`가 없다. Linux 빌드는 현재 바로 되지 않는다.

## 외부 배포 여부 (FMOD · DxLib 공식 · vcpkg · MSVC)

조사일 2026-10-27. "확인"은 공식 페이지나 공식 패키지에서 직접 읽은 것, "미확인"은 접근 불가·2차 출처다.
fmod.com은 JS 앱이라 headless 브라우저로 렌더해서 읽었다. 그 과정에서 Playwright 플러그인이 작업 트리에 `.playwright-mcp/`를 만들었다(미추적, Git 제외 대상 후보).

| 의존성 | Windows ARM64 | macOS arm64 | 확인 | 출처 |
|---|---|---|---|---|
| FMOD Core 2.03 | 네이티브 제공. 플랫폼 페이지에 "x86, x64, ARM64 - optimized with NEON", `api/core/lib/$ARCH/fmod_vc.lib`. ARM64 빌드는 VS2019 v142 이상. 2.02.xx 패치 중 추가됨 | 제공. "x86_64 and arm64 back to macOS 10.13", 단일 universal `libfmod.dylib` | 확인 (2.03.15, 2026-09-21 문서). SDK zip 내부 arm64 폴더명은 다운로드가 로그인 게이트라 미확인 | fmod.com/docs/2.03/api/platforms-win.html, platforms-mac.html |
| FMOD 라이선스 | Indie 무료: 연매출 $200k 미만·개발예산 $600k 미만, 프로젝트 등록 필수. 모든 등급에 인앱 크레딧 문구 + 시작 화면 FMOD 로고 필수(Indie는 로고 면제 불가) | 동일 | 확인. 비상업/교육 FAQ는 미확인 | fmod.com/licensing, fmod.com/attribution |
| DxLib 공식 | **없음.** 다운로드 페이지·전체 변경 이력(ARM 언급은 Android 1건)·3.25a 소스 프로젝트(Win32만)·VC 패키지 216MB(x86/x64 lib만, "arm" 항목 0) | **없음.** 비Windows 데스크톱은 서드파티 MIT `dxlib-for-linux`뿐 | 확인(부재) | dxlib.xsrv.jp/dxdload.html, dxlog.html, DxLibMake3_25a.zip, DxLib_VC3_25a.zip |
| DxLib 버전 | 최신 3.25a(2026-08-23). vendored 3.24f는 2025-03-21, 한 릴리스 뒤 | | 확인 | dxlog.html |
| DxLib 라이선스 | 수정·재배포 허용. 소스/라이브러리 재배포 시 "DX Library Copyright (C) 2001-2026 Takumi Yamada." + 사용 기능의 서드파티 고지 동봉. 라이선스 비용 없음, 크레딧 의무 없음 | 동일 | 확인 | dxlib.xsrv.jp/dxlicense.html, dep/DxLib/DxLib.txt |
| vcpkg 9개 포트 (libjpeg-turbo, libogg, libpng, libtheora, libvorbis, opus, opusfile, tiff, zlib) | `arm64-windows`는 비커뮤니티·CI 대상 triplet. 9개 모두 `ci.baseline.txt`에 fail/skip 항목 없음 = CI 통과 기대 | `arm64-osx`가 macOS 유일 CI triplet. 9개 모두 항목 없음 | 확인(CI 기대값). 실제 빌드는 안 함 | microsoft/vcpkg master ci.baseline.txt, triplets/, azure-pipelines.yml |
| MSVC · CMake | VS 2022 17.4+ 네이티브 ARM64 툴셋. CMake `Visual Studio 17 2022` 제너레이터 `-A ARM64` | | 확인 | learn.microsoft.com, cmake.org |

참고: `vcpkg.json`에 `libtheora`가 두 번 적혀 있다. 동작에는 영향 없고 정리 대상이다.

### Windows ARM64 장애 판정

- 비장애: FMOD(공식 ARM64 바이너리 존재, 저장소에 vendored 사본과 CMake 분기만 없음), vcpkg 9개, MSVC/CMake 툴체인.
- 장애: **DxLib.** 공식 ARM64 빌드·프로젝트·lib·이력이 어느 버전에도 없다. vendored 소스를 직접 ARM64로 컴파일해야 하고, 그 범위는 위 DxLib 감사대로 `DxWindow.cpp` 한 블록이다. 라이선스는 이를 허용한다.
- 런타임 미확인: d3dx9_*.dll·X3DAudio1_*.dll ARM64 부재 시 폴백 동작.

### macOS arm64 장애 판정

- 비장애: FMOD(universal dylib), vcpkg 9개.
- 장애: **DxLib.** 공식 macOS 포트가 없다. 유일한 비Windows 포트 `dxlib-for-linux`(X11/EGL/GLES/OpenAL)는 README가 사운드·동영상 등 다수를 미검증으로 표시한다. macOS는 그 위에 새 포트를 얹거나 렌더 계층을 바꿔야 한다. CMake에도 Darwin FMOD 분기가 없다("No FMOD for this platform").
- 라이선스: FMOD Indie 등록·크레딧·로고, DxLib 저작권 문구·서드파티 고지.

## 미검증

- ARM64 configure·build·링크·실행. 위 결론은 전부 정적 조사다.
- d3dx9 없는 D3D9 셰이더 경로, X3DAudio 미로드 시 동작.
- `dep/DxLib/Android`, `iOS` 하위 디렉터리는 범위 밖으로 두었다.
