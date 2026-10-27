# preparation scripts

`docs/preparation/ROADMAP.md`의 준비 작업을 실기기에서 재현하고 근거를 남기는 스크립트를 둔다.
현재는 WIN-01 하나다.

## win01-baseline.ps1

### 목적

`.github/workflows/build.yml`의 기준 빌드 절차(`cmake --preset windows-vs-x64` →
`cmake --build --preset windows-vs-x64-relwithdebinfo`)를 로컬 Windows 11 x64 기기에서 재현하고,
산출물의 PE 아키텍처·해시, 원본 LR2 배포본의 해시, 기동 결과를 JSON과 로그로 남긴다.
ROADMAP의 WIN-01 행이 요구하는 완료 근거는 **configure/build 로그 + exe/DLL machine 검사 + 기동**이다.
이 스크립트의 출력이 그 근거다.

### 전제 조건

- Windows 11 x64 (ARM64 호스트는 경고만 내고 진행한다. 그 결과는 ACCEPTANCE.md 기준으로 에뮬레이션 결과이며 네이티브 완료로 세지 않는다)
- Visual Studio 2026 Community + "C++를 사용한 데스크톱 개발" 워크로드 (`Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, v145 / MSVC 14.5x)
- `Visual Studio 18 2026` 생성기를 제공하는 CMake(upstream 4.2 이상), git, PowerShell 7 (`pwsh`). VS 2026에 포함된 CMake는 PATH에 자동으로 오르지 않는다.
  VS 18.11 내장본(`<VS>\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`, 4.3.1-msvc1)은 `Visual Studio 18 2026` 생성기를 제공하고 WIN-01 configure/build를 통과했다(2026-10-27). 이 경로를 PATH 앞에 두면 별도 설치가 필요 없다

#### VS 2026 preset

CI(`.github/workflows/build.yml`)는 GitHub 호스트 러너의 VS 2022로 `windows-vs-*` preset을 계속 쓴다.
로컬 기준 빌드는 생성기만 바꾼 `windows-vs2026-*` preset을 쓴다. 컴파일 플래그·vcpkg triplet·출력 이름은 상속받아 같다.
따라서 WIN-01의 결과는 "같은 소스·같은 플래그, 툴셋 v143→v145" 차이를 포함한다. CI 산출물과 비교할 때 이 차이를 함께 적는다.

| configure | build | 비고 |
|---|---|---|
| `windows-vs2026-x64` | `windows-vs2026-x64-relwithdebinfo`, `-debug` | WIN-01 기본값 |
| `windows-vs2026-x64-asan` | `windows-vs2026-x64-asan-debug` | MEM-* 용 |
| `windows-vs2026-x86` | `windows-vs2026-x86-relwithdebinfo` | WIN-01 범위 밖 |

`vcxproj/*.vcxproj`와 `OpenLR2.sln`은 `PlatformToolset v143` 그대로다. VS 2026에서 솔루션을 직접 열면 재대상 지정 안내가 뜬다.
WIN-01은 CMake 경로만 쓰므로 이 파일들을 바꾸지 않는다. 솔루션 경로가 필요하면 설치 관리자에서 v143 빌드 도구 구성 요소를 추가하거나 별도 작업으로 재대상 지정한다.
- 원본 배포본 `LR2_100201.zip` (SHA-256 `34294ea6…ff41`, 54,143,938 바이트). 해시가 다르면 추출하지 않는다
- 네트워크. 스크립트 자체는 vcpkg `git clone`만 하지만, vcpkg bootstrap과 `cmake --preset`이 호출하는 manifest 설치가 vcpkg 바이너리와 port 소스를 내려받는다
- 여유 디스크 20 GiB 이상 권장 (vcpkg 빌드 트리 포함)

### 사용법

```powershell
pwsh -ExecutionPolicy Bypass -File docs\preparation\scripts\win01-baseline.ps1 -ZipPath D:\dl\LR2_100201.zip
```

기동까지 포함하려면 `-Launch -SeedConfig`를 붙인다. 재실행 시 추출 폴더를 덮어쓰려면 `-Force`, 재사용하려면 `-SkipExtract`,
빌드를 건너뛰고 산출물 검사부터 다시 하려면 `-SkipBuild`를 쓴다.

| 매개변수 | 기본값 | 설명 |
|---|---|---|
| `-RepoRoot` | 스크립트 위치 기준 저장소 루트 | `CMakePresets.json`이 있어야 한다 |
| `-ZipPath` | (없음) | `LR2_100201.zip` 경로. `-SkipExtract`가 아니면 필수 |
| `-WorkRoot` | `<repo>\.local\win01` | 로그·추출본·vcpkg가 모두 이 아래에 생긴다 |
| `-VcpkgRoot` | `<WorkRoot>\vcpkg` | 고정 커밋 `cd61e1e2…78e3`으로 checkout |
| `-FmodRelPath` | `dep\FMOD\bin64\fmod.dll` | 검사·스테이징할 FMOD DLL. 지정하지 않고 build preset이 Debug면 `fmodL.dll`로 바꾼다(`CMakeLists.txt` Debug 링크) |
| `-Preset` / `-BuildPreset` | `windows-vs2026-x64` / `windows-vs2026-x64-relwithdebinfo` | CMakePresets.json의 이름. VS 2022 기기면 `windows-vs-x64` / `windows-vs-x64-relwithdebinfo` |
| `-SkipBuild` / `-SkipExtract` / `-Force` | off | 단계 생략·덮어쓰기 |
| `-Launch` | off | 게임 프로세스를 실제로 띄운다 |
| `-LaunchArgs` | `-ns` | 점수 저장 안 함. `-a`(자동 플레이), `-dx9`/`-dx9ex`/`-dx11`, `-test`도 `LR2/Main.cpp`가 받는다 |
| `-LaunchWaitSeconds` | 20 | 프로세스 생존 판정까지 기다리는 시간 |
| `-StopAfterWait` | off | 대기 후 살아 있으면 강제 종료 (SSH 세션에서 프로세스가 남지 않게) |
| `-SeedConfig` | off | `config.xml`이 없을 때 최소 jukebox 경로만 적은 `config.xml`을 쓴다 |

### 단계별 검증 내용

| 단계 | 검증 | 산출 |
|---|---|---|
| environment | 64비트 Windows 여부·아키텍처, pwsh 버전, git commit/branch/dirty, CMake ≥ 3.29, preset 생성기를 `cmake -E capabilities`가 제공하는지, 생성기 번호로 정한 VS 범위(`Visual Studio 18 2026`→`[18.0,19.0)`)의 vswhere 설치본 + VC 툴셋 존재, `cl.exe` 배너(보고만), 여유 디스크. cmake·VS·git 없음만 실패 | `environment.json` |
| vcpkg | clone(없을 때) → 고정 커밋 checkout → bootstrap(없을 때) → 실제 HEAD 기록, `VCPKG_ROOT` 설정 | `NN-vcpkg-*.{out,err}.log` |
| configure / build | preset 그대로 실행, 종료 코드·소요 시간 기록. 실패 시 이후 단계 중단 | `NN-cmake-configure.*`, `NN-cmake-build.*` |
| artifacts | `out\<preset>\RelWithDebInfo\OpenLR2_x64.exe`와 `dep\FMOD\bin64\fmod.dll`의 PE 헤더를 직접 읽어 Machine(0x8664=x64, 0x14c=x86, 0xAA64=ARM64)·64비트 여부·timestamp·SHA-256 기록. x64가 아니면 실패 | `artifacts.json` |
| extract | zip SHA-256·크기 일치 확인 후 `<WorkRoot>\LR2-fresh\`에 추출. 항목 이름은 CP932로 디코드한다(원본 zip은 UTF-8 플래그가 없다). `LR2body.exe`·`LR2.exe`·`fmodex.dll` 해시를 `evidence/input-inventory.json`과 대조(파일 없으면 내장 상수) | `result.json`의 extract 항목 |
| stage | `OpenLR2_x64.exe`·`fmod.dll`을 `LR2-fresh\LR2beta3\`에 복사. 원본 `LR2body.exe`는 비교용으로 그대로 둔다 | `staged.json` |
| launch (`-Launch`) | 작업 디렉터리 `LR2beta3`에서 프로세스 시작, 대기 후 생존·종료 코드·창 제목 기록, `LR2files\Config\*.xml`과 `*.log`/`Log.txt`를 복사 | `launch.json`, `launch\` |
| summary | 표 출력, 필수 단계 하나라도 Failed면 종료 코드 1 | `result.json` |

### 기동 단계에서 알아둘 것

- zip에는 `config.xml`이 없다. OpenLR2는 `config.xml`에 jukebox 경로가 하나도 없으면 모달 오류("JUKEBOX1 …")를 띄우고 -1로 끝난다
  (`LR2/Main.cpp` 시작부). 원본 `LR2.exe` 런처로 한 번 설정하거나 `-SeedConfig`로 `LR2files/Config/` 하나를 등록한 최소 `config.xml`을 만든다.
  `-SeedConfig`는 기존 `config.xml`을 덮어쓰지 않는다.
- `config.xml`만으로는 부족하다. `LR2/Main.cpp`는 `LR2files/Database/Score/<player id>.db`가 없으면
  `スコアデータベースが見つかりません。config.exeで作成して下さい。` 창을 띄우고 멈춘다. 이 DB와 `player` 행은 원본 `LR2.exe` 런처가 플레이어 등록 때 만든다.
  `-SeedConfig`는 DB를 만들지 않는다. 대화형 세션에서 `LR2.exe`로 플레이어를 한 번 등록한 뒤 `-SkipBuild -SkipExtract -Launch`로 다시 돌린다.
- SSH·서비스 세션에서 띄운 GUI는 콘솔 데스크톱에 보이지 않고 `Process.MainWindowTitle`도 비어 있다(숨김 창은 대상이 아니다).
  그래서 `EnumWindows`로 PID의 최상위 창을 숨김 포함 열거해 `launch.json`의 `windows`에 클래스·제목·Static 본문을 남긴다.
  살아 있는 프로세스에 `#32770`(MessageBoxA) 창이 있으면 `blockedByErrorDialog`·`errorDialogText`를 채우고 launch를 Failed로 기록한다.
  초판은 `MainWindowTitle`만 봐서 위 스코어 DB 오류창을 놓치고 Passed로 기록했다(2026-10-27 수정).
- 오류창이 없고 살아 있다는 것은 시작 검사를 통과했다는 뜻일 뿐이다. SSH 비대화형 세션에서 D3D 장치·창이 실제로 만들어지는지는
  이 스크립트로 확인하지 않았다. 타이틀 화면 도달은 콘솔(또는 RDP·Moonlight) 세션에서 눈으로 확인한다.
- `openlr2-config.xml`은 정상 종료 시점에 쓰인다. 살아 있는 채로 끝내면 없을 수 있다.

### 검증하지 않는 것

- 실제 게임플레이·판정·리플레이 (QA-01)
- 오디오 출력·ASIO (ASIO-01)
- 입력 장치
- 4K·DPI·창 전환 (UHD-01/02)
- 메모리·누수 (MEM-*)
- ARM64 네이티브 (ARM-01/02). ARM64 호스트에서 돌리면 x64 에뮬레이션 결과로만 기록된다
- x86 빌드. preset 매개변수로 돌릴 수는 있지만 exe 이름·FMOD 경로(`-ExeName`, `-FmodRelPath`)를 같이 바꿔야 하고 WIN-01 범위가 아니다

### 출력 위치

```
<WorkRoot>\                         기본 <repo>\.local\win01
  vcpkg\                            고정 커밋 vcpkg
  LR2-fresh\LR2beta3\               추출본 + 스테이징된 OpenLR2_x64.exe, fmod.dll
  logs\<yyyyMMdd-HHmmss>\
    environment.json  artifacts.json  staged.json  launch.json  result.json
    NN-<step>.out.log / .err.log
    launch\                         기동 후 수집한 xml/log
<repo>\out\windows-vs2026-x64\      CMake가 만드는 빌드 트리(preset의 binaryDir = out\<preset 이름>)
```

`/.local/`과 `out/`은 `.gitignore`에 있다. WorkRoot 출력이 커밋에 섞이지 않는다.
공유용 결과는 ACCEPTANCE.md의 "결과 파일" 규약대로 환경·커밋·입력 해시·명령·미검증 항목을 따로 적는다. `result.json`과 `environment.json`이 그 원자료다.

### 검증 상태

- macOS pwsh 7.6.8에서 구문 파싱 통과, alias 미사용 확인
- macOS에서 환경 단계 실패→전체 Skipped→`result.json`·종료 코드 1 흐름 확인
- PE 헤더 읽기는 `dep/FMOD/bin64/fmod.dll`(0x8664)·`bin86/fmod.dll`(0x14c)로 확인, 해시가 `input-inventory.json`과 일치
- CP932 zip 항목 이름 디코드는 합성 zip으로 확인
- (VS 2026 전환) `CMakePresets.json` JSON·`cmake --list-presets` 파싱 통과, `Get-PresetGenerator`가 `windows-vs2026-x64`·`-asan`·`-x86`→`Visual Studio 18 2026`/`[18.0,19.0)`, `windows-vs-x64`→`[17.0,18.0)`, 없는 이름→예외로 동작하는 것을 macOS pwsh에서 확인. `cmake -E capabilities`의 VS 생성기 목록과 VS 2026 vswhere 조회는 Windows에서만 확인 가능
- Windows 실기기 1차 실행(2026-10-27, WIN-DESKTOP: Windows 11 build 26300 x64, pwsh 7.6.6, VS Community 2026 18.11.12324.101, cl 19.51.36260, VS 내장 CMake 4.3.1, 커밋 `29044f2`, SSH High integrity 세션)
  - environment·vcpkg(clone 24s, checkout `cd61e1e2…`, bootstrap)·configure(207s)·build(129s)·artifacts·extract·stage Passed
  - `OpenLR2_x64.exe` Machine 0x8664, SHA-256 `85f168b2…2087` / `fmod.dll` 0x8664, `5767ca88…d483` (`input-inventory.json`과 일치)
  - zip·`LR2body.exe`·`LR2.exe`·`fmodex.dll` 해시가 inventory와 일치, CP932 이름 추출 정상
  - build 로그의 MSVC 경고 상위: C4100 54, C4244 42, C4505 26, C4456 20 (실패 없음)
  - launch: 초판은 Passed로 기록했지만 거짓 양성이었다. 숨김 창 열거로 스코어 DB 오류창을 확인했고, 수정본은 같은 상태를 Failed로 기록한다
- 대화형 기동(같은 날, 콘솔 세션). 바탕화면 cmd로 `LR2.exe` 런처에서 플레이어 `TEST` 등록 → `OpenLR2_x64.exe -ns`
  - 사용자가 타이틀 화면을 눈으로 확인, Esc 정상 종료 exit 0, 종료 시 `openlr2-config.xml` 생성
  - 실행 중 `d3d9.dll`·`d3dx9_43.dll`·`dxgi.dll`·NVIDIA UMD·`fmod.dll`·`dinput8.dll` 로드, 모니터 3대(4K, 144dpi) 인식
  - 런처는 닫히면서 원본 `LR2body.exe -s`도 띄운다. 같은 폴더의 DB를 동시에 쓰지 않도록 SSH에서 강제 종료했다. 같은 cwd라 `Log.txt` 귀속은 시작 시각·내용으로만 판단했다
- SSH 재실행(DB 있음, 로그 `20261027-150121`): 오류창 없이 최상위 창 `OpenLR2 version 261001`(DxLib 메인 창)·`DIEmWin` 생성, launch Passed.
  단 DxLib이 디스플레이를 `WinDisc 0x0 0bit`로 인식한다. SSH 결과는 시작 검사 통과 근거일 뿐 렌더링 근거가 아니다
- 원본 단독 기동(같은 날, 콘솔 세션, 사용자 육안): `LR2body.exe`가 `LR2 beta3 version 100201` / `PUSH ANY KEY` 타이틀을 띄우고 키 입력 후 게임 화면으로 넘어간다.
  이 실행은 `Log.txt`를 쓰지 않았고 `Score\TEST.db`도 바꾸지 않았다(`config.xml`·`midi.xml`·`song.db`·`SkinCustomize\*.xml`만 갱신)
- 런처가 만든 새 DB에서 포크가 `ハッシュが不正です。プレイヤースコアデータを初期化しました。`를 남기는 것(`LR2/LR2_statlong.cpp:129-151`)은 회귀가 아니다.
  런처는 `player` 행을 `scorehash` NULL·통계 NULL로 만들고, `scorehash`는 플레이 후 `UpdatePlayerStat`만 쓴다. upstream 원본 디컴파일 소스(`LR2Beta3-v100201` `583a385`, `LR2f.cpp`)의
  `MakePlayerStatHash`와 초기화 분기가 포크와 같다. 근거는 DB 행 조회와 소스 비교이며, 원본 실행 로그로는 확인하지 못했다
- 미검증: 게임플레이·입력·오디오 출력(QA-01·ASIO-01 범위), 원본과의 동작 비교

## update-readme-status.py

루트 `README.md`의 `<!-- fork-status:start -->` ~ `<!-- fork-status:end -->` 사이를 GitHub Project
[OpenLR2 Modernization](https://github.com/users/OE-Park/projects/2)의 현재 상태로 다시 쓴다. 표식 밖은 건드리지 않는다.

- 필요: `gh` 로그인 + `project`(또는 `read:project`) 권한
- 실행: `python3 docs/preparation/scripts/update-readme-status.py` (`--dry-run`은 출력만)
- 내용: 상태별 개수와 필터 링크(`views/1?filterQuery=status:"…"`), In Progress 카드 표, 생성일(KST)
- 보드 카드 Status를 바꾼 뒤 실행하고 README 변경을 커밋한다. 자동 실행(GitHub Actions)은 없다
- 검증: 2026-10-27 macOS에서 실행, 같은 보드 상태로 재실행 시 README 바이트 동일
