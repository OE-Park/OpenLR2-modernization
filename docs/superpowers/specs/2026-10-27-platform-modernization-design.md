# OpenLR2 호환 우선 플랫폼 현대화 설계 초안

작성일 2026-10-27. **방향 선택 완료, 상세 설계 검토 대기, 구현 미착수.**
현황 근거와 진행 상태의 원본은 [PROJECT-STATUS.md](../../../PROJECT-STATUS.md)다.

## 목적

LR2의 곡·스킨·판정·리플레이·점수 호환을 유지하면서 Windows 11 x64, Windows 11 ARM64,
macOS arm64에서 실제 플레이 가능한 네이티브 앱을 만든다. 메모리 누수를 줄이고 3840×2160 출력까지 안정화한다.
사용자는 기존 호환 우선과 Windows x64 기준 확보 후 백엔드 분리 방향을 선택했다.

## 접근 방식

| 접근 | 장점 | 비용/제약 | 결정 |
|---|---|---|---|
| 기존 Windows 앱 유지 + 호환 실행 계층 | 원본 동작 비교와 초기 사용에 유리 | ARM/macOS 네이티브 지원 근거가 되지 않음 | 비교 도구로만 사용 |
| 기존 게임 로직 유지 + 플랫폼 경계 분리 | 기존 스킨·판정 비교 가능, 단계별 검증 가능 | DxLib·오디오·파일·입력 API 접점을 조사·교체해야 함 | 사용자 선택 방향 |
| 새 크로스플랫폼 엔진으로 일괄 재작성 | 엔진 내부 구조를 처음부터 정리 가능 | 판정·스킨·리플레이 호환 재구축 범위가 큼 | 현 단계에서 선택하지 않음 |

이 결정은 최종 그래픽/오디오 SDK의 선택까지 의미하지 않는다. 새 백엔드는 최소 흐름 spike로 호환성과 의존성을 먼저 확인한다.

## 현재 제약

- 소스 CMake는 Windows/Linux 경로이며 Apple 경로가 없다. Linux 지원은 upstream README에서도 개발 목적이다.
- 64비트 포인터만으로 x64 FMOD·산출물 이름을 선택한다. Windows ARM64 지원은 CPU와 ABI 기준으로 다시 설계해야 한다.
- vendored FMOD DLL은 x86/x64다. ARM64/macOS용 SDK 또는 대체 경로의 ABI·기능·배포 조건을 확인해야 한다.
- `#RESOLUTION,3`은 스킨에서 4K를 처리하지만 전역 resolution은 0/1/2만 매핑한다.
- 스킨 목록에 raw malloc/realloc와 누수 FIXME가 있다. 메모리 문제를 플랫폼 이식과 한 번에 바꾸면 원인 분리가 어렵다.
- GAR 프로그램 `LR2body.exe.1.1`과 ZIP의 LR2body.exe가 같은 바이트인지 아직 모른다. 기존 분석 DB를 비교 기준으로 쓰기 전에 digest를 확인한다.
- REA 로컬 빌드·호환 Node 준비와 PE import 분석은 완료했다. Ghidra 미설정으로 GAR 복원·함수 분석은 아직 없다.

## 구조와 변경 경계

게임 로직(차트·타이밍·판정·점수·리플레이·스킨 명령)은 유지하며 다음 경계를 얇게 나눈다.

| 경계 | 기존 접점 | 구현자가 정할 것 |
|---|---|---|
| 창·렌더·texture/BGA | En_graphic, LR2_skinload/skindraw, DxLib 호출 | 기존 Windows 경로 보존, 새 렌더 API 범위와 장치 손실 처리 |
| 오디오 | En_audio, LR2_audio, FMOD/DxLib | native SDK 가용성, 저지연 출력과 DSP/codec 동등성 |
| 입력·MIDI·시계 | En_input, En_timer, Main | event timestamp·scratch semantics·monotonic clock, host별 device 처리 |
| 파일·문자·설정 | En_fileutil, CSTR, XML/DB | UTF-8 경계, path normalization, 대소문자·읽기 전용·사용자 데이터 위치 |
| 플러그인·IR | LR2_customir/ExampleIR | OS/CPU ABI·이름·로드 오류, 기존 모듈 호환 범위 |
| 자원 소유권 | SkinManage, CSTR, sound/graph handles | 객체 수명·해제 책임·비동기 종료 순서 |

선택할 라이브러리는 추측으로 확정하지 않는다. 각 후보는 Windows x64/ARM64·macOS arm64의 native build,
오디오 지연·scratch·BGA·DXA/skin 호환을 최소 한 곡 흐름에서 비교한 뒤 ADR로 남긴다.
전용 API가 가용하지 않으면 기능별 대체·명시적 미지원 상태를 정하고 이를 완전 지원으로 보고하지 않는다.

## 메모리 전략

먼저 Windows x64 기준값과 재현 입력을 고정한다. 스킨 목록의 할당·확장·실패·재초기화·종료 경로를 추적하고,
가능한 최소 범위에서 소유권을 RAII로 이동한다. CSTR의 생성/복사/파괴 규칙을 확인하기 전 단순 vector 치환을 하지 않는다.
sound·graph·BGA는 success/failure/cancel/restart/close를 같은 소유자가 정리하도록 설계한다.
사용량 감소율을 목표로 먼저 선언하지 않고, 미해제 할당 스택과 반복 live resource 증가를 수정 전후 비교한다.

## 해상도 전략

SD/HD/FHD/UHD 매핑과 custom dimension 검증을 하나의 명세로 모은다. 스킨 명시값 우선, 미지정 시 전역값을 사용한다.
기존 논리 좌표를 보존하고 display DPI와 실제 drawable 크기를 분리한다. 기존 SD 스킨의 강제 16:9 재해석을 피한다.
렌더 타깃 재생성 실패 시 상태·오류·정리 규칙을 정의한다. 4K 설정 UI만 추가하고 지원 완료로 처리하지 않는다.

## 추가 요구사항 (2026-10-27, 사용자 지시)

사용자가 세 가지를 추가했고, 같은 날 IR 제외 조건을 더했다. 아래 "현재 상태"는 소스 정적 조사이고 실행 검증이 아니다. 상세 설계는 아직 승인되지 않았다.

| 요구 | 현재 상태 (소스 근거) | 설계에서 정할 것 |
|---|---|---|
| **런처.** [LR2Nexus](https://github.com/Unengine/LR2Nexus) (GPL-3.0)를 참고해 개발 | LR2Nexus는 C# .NET 9 + Avalonia 12 데스크톱 앱(2026-07-12 HEAD `8de8053`, cs 42개). `config.xml`을 Shift-JIS로 읽고 쓰며(`XmlReflectionEngine.cs:23`), `I18nManager.cs`로 UI 다국어, NAudio로 오디오 장치 열거, SQLite로 점수 DB 접근. 저장소 README는 "vanilla LR2·OpenLR2 모두 지원". 현재 OpenLR2 저장소에는 런처 코드가 없고 README가 외부 런처 둘을 소개만 한다 | (1) 형태: 별도 프로세스 런처 vs 엔진 내장 설정 화면. (2) 언어·툴킷: LR2Nexus 코드를 가져오면 그 부분은 GPL-3.0이고 OpenLR2에는 최상위 LICENSE가 아직 없어 **라이선스 결정이 선행**된다. 참고만 하고 새로 쓰면 설정 스키마·기능 목록만 가져온다. (3) 세 플랫폼에서 같은 런처를 쓸지(Avalonia는 macOS 가능) |
| **다국어 지원.** 원본이 유니코드 기반이 아님 | 포크는 내부를 UTF-8로 바꿨다: 매니페스트 `activeCodePage=UTF-8`, `Main.cpp:268-269` DxLib 문자 코드 UTF-8, 스킨 폰트 `DX_CHARSET_UTF8`(`LR2_skinload.cpp:1004`). 원본 호환을 위해 CP932 변환이 남아 있고 `ansi2utf/utf2ansi`는 932 외 코드페이지를 assert로 거부(`En_fileutil.cpp:103,113`), 곡 DB CRC는 `cp_user_had_in_lr2 = 932` 고정(`:594`). `932` 리터럴 37곳. `config.system.language`는 XML에 읽고 쓰기만 하고 소비처가 없다. UI 문자열은 스킨이 그리므로 엔진 자체 문구는 적고, 오류 로그는 일본어 하드코딩 | (1) "다국어"의 범위: 파일명·경로·곡 메타의 임의 언어, IME 검색 입력, 스킨 폰트의 CJK 렌더, 엔진 메시지 번역, 런처 UI 번역. (2) 기존 점수·곡 DB의 CP932 기반 해시 호환을 어디까지 유지할지(한국어 로케일 사용자 DB는 원본에서 이미 다른 CRC). (3) 비Windows의 iconv 경로 |
| **인터넷 랭킹(IR) 제외 조건.** 오디오 라이브러리·출력 경로를 바꾸면 지연 등 환경이 달라져 랭킹 커뮤니티가 기록을 거부할 수 있다. 사용자 결정: **macOS 빌드는 IR 기능을 제거**한다 | IR 경로 두 개. (a) 레거시 LR2IR: `LR2_ir.cpp`가 `dream-pro.info/~lavalse/LR2IR/2/*.cgi`로 송수신, 파일 첫 줄에 "deprecated", README는 LR2IR 종료를 명시. (b) CustomIR: `LR2files/CustomIRs/<모듈>/`의 네이티브 모듈을 로드(`LR2_customir.cpp:102`), `SendScoreV1`로 점수 전송(`LR2_customir_api.h:286`), 선곡·결과 화면이 랭킹 표시에 사용(`Scene02_Songselect.cpp:1823`, `Scene05_Result.cpp:201`). 알려진 모듈은 Bokutachi. 서버에는 `openlr2::clientName`·`versionCode`가 간다(`LR2_ir.cpp:556`). 원본 LR2는 FMOD Ex(`fmodex.dll`), 포크 Windows는 FMOD Core 2.03이라 "원본과 같은 오디오"는 이미 아니다. 현재 기준 환경은 포크 Windows x64 + FMOD 2.x | (1) 제거 방식: 빌드 옵션으로 IR 코드(레거시 LR2IR·CustomIR 로더·랭킹 표시)를 컴파일에서 빼는 것을 권장. 실행 중 설정 끄기는 사용자가 다시 켤 수 있어 약하다. (2) 기준 오디오 정의: "IR 허용 = Windows + FMOD Core 2.x(WASAPI/ASIO)"로 둘지. (3) Windows ARM64(같은 FMOD, 다른 아키텍처·드라이버 경로)의 IR 허용 여부는 미결. (4) IR이 없는 빌드에서 로컬 점수 DB는 그대로 저장할지, 다른 오디오 환경 점수임을 구분할지. (5) 랭킹 화면 요소가 있는 스킨에서 IR 부재를 명확히 표시 |
| **ASIO (Windows 한정)** | FMOD 출력 선택이 이미 있다: `config.sound.output` 0/1=WASAPI, 2=ASIO(`En_audio.cpp:1069-1080`), 실패 시 AUTODETECT 폴백, `output==2`면 DSP 비활성(`LR2_configsave.cpp:1050`). 드라이버는 `config.sound.driver` 인덱스. 설정 UI에서 고르는 수단은 미확인(런처 역할) | (1) ASIO 장치 열거·선택을 런처/설정 화면 중 어디서 할지. (2) 버퍼 크기·지연 측정 기준. (3) ARM64 Windows에서 FMOD ASIO 출력 가용성(미확인). (4) macOS는 CoreAudio로 명시 미지원 처리 |

### IR 관련 외부 의견 (2026-10-27 웹 조사)

공식 정책이 아니라 커뮤니티 논의·개인 블로그다. 날짜가 오래된 자료가 섞여 있다.

- LR2IR은 2026-05-31 종료됐고, OpenLR2 소스 공개도 같은 날이다([NamuWiki](https://en.namu.wiki/w/Lunatic%20Rave%202), [LR2 unofficial site](https://lr2.sakura.ne.jp/)). 현재 OpenLR2의 실사용 IR은 CustomIR 모듈 [BokutachiIR_OpenLR2](https://github.com/marysiamzawka/BokutachiIR_OpenLR2)다. [BMS Community Resources](https://bms-community.github.io/resources/)에는 Bokutachi 지원 클라이언트가 LR2·LR2oraja·beatoraja(PMS 한정)로 적혀 있다.
- 판정 체계가 다른 클라이언트의 점수를 같은 랭킹에 섞는 것에 대해 beatoraja 메인테이너는 "다른 무대의 스코어를 비교하는 것은 경쟁적으로 큰 의미가 없다", "IR 운영 부담이 이점보다 크다"고 했다. 다른 참가자들도 "같은 본체에서 두 판정을 쓰면 IR에서 구분이 필수"라고 했다([beatoraja Discussion #668](https://github.com/exch-bms2/beatoraja/discussions/668)). 거기서 논의된 차이는 판정 폭·게이지·LN·TOTAL이었고, 오디오 백엔드는 다뤄지지 않았다.
- 비공식 Q&A: 공식 배포가 아닌 빌드(예: LR2oraja)는 beatoraja용 IR에 접속할 수 없다. 기본 OpenAL 출력은 지연이 큰 편이고 PortAudio로 바꾸면 줄어들 수 있다. 지연은 "개인 환경 의존이 심하다"([beatoraja 非公式Q&A](https://mirai-yokohama.sakura.ne.jp/bms/beatoraja/)). 즉 IR 운영자는 **클라이언트 빌드 단위**로 접속을 통제하고, 오디오 지연은 사용자 오프셋 보정 문제로 다뤄진다.
- 해석: 커뮤니티가 랭킹을 분리하는 직접 기준은 판정·게이지 로직과 클라이언트 식별이다. 오디오 백엔드 교체만으로 거부한 사례는 찾지 못했다. 그래도 IR 운영자가 클라이언트 단위로 허용 여부를 정하므로, 검증 기준 환경과 다른 macOS 빌드에서 IR을 빼는 결정은 운영자 판단을 앞지르지 않는 보수적 선택이다.

## 이번 준비 범위와 이후 범위

이번 준비는 소스 복제, 입력 자료 식별/보존, 근거 조사, 설계/백로그/검증 절차 작성이다.
게임 코드·CMake·CI·배포는 이후 구현 단계다. 판정 체계 변경, 온라인 서비스, 기존 개인 점수 DB 변경은 별도 요구사항이다. 런처·다국어·ASIO는 위 추가 요구사항 표를 따른다.

구현 순서는 [ROADMAP](../../preparation/ROADMAP.md), 인수 기준은 [ACCEPTANCE](../../preparation/ACCEPTANCE.md),
REA 재개는 [REA-RUNBOOK](../../preparation/REA-RUNBOOK.md)을 따른다.
기준 장비·최소 OS·지원 컨트롤러 목록은 baseline 단계에서 기록한다. 설계자는 native ARM64를 목표로 잡았으며,
오디오/렌더 SDK의 최종 선택과 성능 허용 폭은 측정 후 결정할 구현자 판단으로 남겼다.

## 승인 이후

상세 설계 검토를 받은 뒤 변경 파일·회귀 테스트·실행 환경·작업 분할을 포함한 구현 계획을 작성한다.
현재 문서에 적힌 플랫폼 지원·누수 개선·4K 안정화는 구현 완료 사실이 아니다.

## 설계 검토

별도 C++ 크로스플랫폼 리듬게임 관점의 builder check에서 중요한 누락 없음으로 검토했다.
이 검토는 구현·실기기·성능 검증이나 사용자 상세 설계 승인을 대신하지 않는다.
