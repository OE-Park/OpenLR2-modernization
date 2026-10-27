# QA-01 합성 테스트 자산

QA-01(ROADMAP P0)의 고정 입력이다. 원본 LR2와 포크(OpenLR2)를 같은 chart·옵션·seed로 돌려
판정·점수 차이를 비교하고, `선곡→플레이→결과→선곡` 100회 메모리 루프의 입력으로 쓴다.
ACCEPTANCE.md의 "공통 기능" 항목 중 chart 입력으로 검사할 수 있는 것을 전부 한 세트로 만든다.

이 폴더에는 생성기와 설명만 둔다. WAV·BMP·BMS 결과물은 저장소 밖(`.local/`, gitignore 404행)에
생성하며 커밋하지 않는다.

| 파일 | 역할 |
|---|---|
| `make_synthetic_charts.py` | 키음 WAV, BGA BMP, 5/7/9/10/14키 chart, i18n 폴더, 오류 chart, manifest.json 생성 |
| `make_skin_resolution_variants.py` | 원본 LR2 스킨을 복사해 `#RESOLUTION,n` 변형 스킨 생성 (UHD-01용) |

둘 다 Python 3 표준 라이브러리만 쓴다. 외부 패키지 없음.

## 생성기 실행

```bash
# 기본 출력: <repo>/.local/qa/synthetic (gitignore 대상)
python3 docs/preparation/qa/make_synthetic_charts.py

# 다른 위치, seed 지정, 기존 출력 교체
python3 docs/preparation/qa/make_synthetic_charts.py --out /path/to/qa_songs --seed 1 --force
```

- 출력 루트에 이미 생성 폴더나 `manifest.json`이 있으면 종료 코드 2로 거부한다.
  `--force`는 이 스크립트가 만드는 다섯 폴더와 `manifest.json`만 지운다. 다른 파일은 건드리지 않는다.
- 같은 seed면 결과 바이트가 동일하다. 파일 안에 시각 정보를 넣지 않는다.
  seed는 BGA 프레임 색과 BGM 음열만 바꾼다. chart 텍스트와 키음 음높이는 seed와 무관하다.
- 끝에 시나리오별 파일 수·바이트와 chart별 예상 노트 수를 표로 찍는다.
  예상 노트 수는 생성한 chart 텍스트에 `LR2_songmanage.cpp` `ParseBMSMETA`(2991-3082행)의 셈법을 그대로 적용한 값이라
  선곡 화면의 노트 수와 대조할 수 있다. 셈법: `#IF 1` 외 분기 무시, `#LNOBJ` 객체 제외,
  채널 51-69는 -40·31-49는 -20으로 옮긴 뒤 11-29의 객체를 1개씩 센다(LN 양 끝·숨은 노트도 1개, 0.5 분기는 도달 불가).
  예: `7key_core` 75, `7key_lnobj` 19, `7key_random` 31(공통 앞 8 + 분기 16 + 공통 뒤 7).
- 검증은 `python3 -I`(격리 모드)로도 같은 결과가 나와야 한다. 이 문서의 실행 결과는 전부 `-I`로 얻었다.

### 출력 구조

```
<out>/                              ← LR2에 등록할 곡 루트
  manifest.json                     ← 모든 파일의 경로·크기·SHA-256·시나리오, 생성기 버전, seed
  ascii_basic/                      ← 모드별·기능별 chart 9개 + 키음·BGA 세트
    7key_core.bms  7key_base62.bms  7key_lnobj.bms  7key_scroll.bms  7key_random.bms
    5key.bms  9key.pms  10key_dp.bms  14key_dp.bme
    k01.wav … k16.wav  k_0a.wav  k_a0.wav  k_zz.wav  bgm.wav  muon.wav
    frame01.bmp … frame06.bmp  stagefile.bmp  banner.bmp
  日本語 曲名 テスト/               ← 7key_core를 일본어 제목으로: UTF-8 판 + CP932 판, 일본어 파일명 키음
    7key_core_ja_utf8.bms  7key_core_ja_cp932.bms  鍵音02.wav  (+ 같은 키음·BGA 세트)
  한국어 곡 테스트/                 ← UTF-8 판만 (한글은 CP932로 표현 불가), 한글 파일명 키음
    7key_core_ko_utf8.bms  건반02.wav  (+ 같은 키음·BGA 세트)
  case_mismatch/                    ← chart는 K01.WAV/FRAME01.BMP 대문자 참조, 파일은 소문자
    7key_core_upper.bms  (+ 같은 키음·BGA 세트)
  broken/                           ← 크래시 없이 처리해야 하는 오류 chart
    missing_refs.bms  bpm_zero.bms  truncated.bms  empty.bms  k01.wav
```

규모(seed 1 기준): 파일 127개, 2,493,773바이트. 폴더당 약 650KB.

- 키음 `k01`~`k16`: 44.1kHz 모노 16비트 120ms 사인파, 5ms 페이드. A3(220Hz)부터 온음 간격이라
  이웃 슬롯이 귀로 구분된다.
- `bgm.wav`: 22.05kHz 모노 8초, 120BPM 8분음표 펄스. 키음과 샘플레이트를 다르게 둬서 리샘플링 경로도 탄다.
- `muon.wav`: 100ms 무음. BGM 채널(01)에 BGM과 함께 놓는다.
- BMP: 24비트 BI_RGB 64×48, 1px 흰 테두리. `frame05`는 POOR(채널 06)용 빨강,
  `frame06`은 LAYER(채널 07)용 검정 배경+초록 사각형(검정 = 투명).
- 네 곡 폴더의 공통 파일(`k01`~`k16`, `bgm`, `muon`, `frame01`~`06`, `stagefile`, `banner`)은
  해시가 전부 같다. 폴더 이름·chart 인코딩·참조 대소문자만 다르다.

## 시나리오 표

| chart / 폴더 | ACCEPTANCE 항목 | 원본 vs 포크에서 볼 것 |
|---|---|---|
| `ascii_basic/7key_core.bms` | 7키, scratch, 동시 입력, 롱노트, BPM/STOP, 리플레이, 키음·BGA | 같은 입력(자동 플레이 또는 리플레이)에서 판정 분포·점수·콤보 일치. 3마디 채널 03(150BPM)·4마디 `#BPM01`(180)·5마디 `#BPM02`(120)+`#STOP01`(1000ms) 전후 노트의 realtime. 6마디 LN 4개(1·6번 레인 동시, 5번, scratch) 시작/종료 판정. BGA base 4프레임·poor·layer 로드/해제 |
| `ascii_basic/7key_base62.bms` | 키음 로드(`#BASE 62`) | 1마디 2번 레인(`0a` → `k_0a` 110Hz)과 3번 레인(`0A` → `k10`)이 다른 음으로 들려야 한다. base36으로 잘못 읽으면 둘 다 10번으로 겹쳐 같은 음이 난다. 2마디 7번 레인 `a0`(2232, ZZ 초과)과 7마디 scratch `zz`(3843, `SINGLESLOTS-1`) 재생 |
| `ascii_basic/7key_lnobj.bms` | 롱노트 | `#LNOBJ 0Z` 방식 LN이 `7key_core` 6마디와 같은 모양으로 판정되는지. 종료 객체(`muon.wav`) 소리 없음 |
| `ascii_basic/7key_scroll.bms` | BPM/STOP 확장(`#SCROLLxx`, `#xxxSC`) | 2마디 0.5배, 4마디 2배, 6마디 1배. 노트 realtime은 바뀌지 않고 표시 속도만 바뀌어야 한다 |
| `ascii_basic/7key_random.bms` | random seed 고정 비교 | `#RANDOM 2`로 2·3마디가 원본/미러 중 하나. 같은 seed·같은 리플레이에서 같은 분기가 뽑혀야 한다 |
| `ascii_basic/5key.bms` | 5키 모드 | 키모드 5로 분류, scratch, 3마디 코드, 4마디 LN(채널 51) |
| `ascii_basic/9key.pms` | 9키 모드 | 채널 11-15+22-25가 버튼 1~9로, 채널 65가 버튼 9 LN으로 매핑 |
| `ascii_basic/10key_dp.bms` | 10키 모드, 양쪽 scratch 동시 | 키모드 10, 2P 채널 21-25/26, 채널 63 LN |
| `ascii_basic/14key_dp.bme` | 14키 모드 | 키모드 14, 2P 28/29, 채널 69 LN |
| `日本語 曲名 テスト/` | 일본어 파일명·공백 경로·UTF-8 vs CP932 | CP932 판은 원본 LR2에서 제목·`鍵音02.wav`(2번 레인) 정상. UTF-8 판은 원본에서 제목이 깨지고 2번 레인이 무음이어야 "원본 동작"이다. 포크에서 둘 다 정상이면 그 차이를 I18N-01에 기록 |
| `한국어 곡 테스트/` | 한국어 파일명·공백 경로 | 원본 LR2(CP932 고정)는 제목 깨짐·`건반02.wav` 무음이 예상 동작. 폴더 자체가 목록에 뜨는지부터 확인 |
| `case_mismatch/` | 대소문자 차이 | Windows·기본 macOS(대소문자 무시 FS)에서는 전 레인 재생. Linux 또는 대소문자 구분 APFS에서는 키음 전부 무음·BGA 없음, 로그에 `FindAltSound: ... not found` |
| `broken/missing_refs.bms` | 없는 파일 검사 | `#WAV01`, `#BMP01`, `#STAGEFILE`, `#BANNER`가 없는 파일. 선곡·플레이·결과가 멈추지 않고 2번 레인(`k01.wav`)만 소리 |
| `broken/bpm_zero.bms` | 없는/잘못된 값 | `#BPM 0`. 로드 거부 또는 재생 중 멈춤 여부를 기록. 원본 동작 미확인 |
| `broken/truncated.bms` | 잘린 파일 | 마지막 줄이 객체 중간에서 끊기고 개행 없음(`#00219:…010`). 로드되면 2마디 7번 레인 노트가 하나 빠질 수 있다 |
| `broken/empty.bms` | 0바이트 파일 | 목록 등록·선택 시 크래시 없음 |
| `manifest.json` | 입력 hash 기록 | 측정 CSV·결과 문서의 "입력 hash" 칸에 manifest의 SHA-256을 쓴다 |
| 100회 루프 | 메모리 기준 2항 | `ascii_basic/7key_core.bms`를 기준 chart로 쓴다. BGA·키음·LN·BPM 변화가 한 곡에 들어 있어 자원 해제를 한 번에 본다 |

읽기 전용 폴더 검사는 생성 후 OS에서 폴더 권한을 바꿔 수행한다. 생성기는 권한을 건드리지 않는다.

## 포맷 결정과 근거

줄 번호는 이 저장소 HEAD `1d263a3`의 `LR2/` 소스 기준이다.

### chart 텍스트 처리

- 매 줄은 `#`으로 시작해야 읽힌다(`LR2_bmsload.cpp:2308-2310`). 주석은 LR2 샘플처럼 `*`로 시작한다.
- 파서는 모든 `#` 줄을 CP932→UTF-8로 변환한 뒤 대문자화해서 키워드를 맞춘다(2312-2315행).
  선곡 메타도 같다(`LR2_songmanage.cpp:3001-3005`). 그래서 UTF-8로 쓴 비ASCII 제목·파일명은 원본에서 깨진다.
  이것이 i18n 폴더에 UTF-8 판과 CP932 판을 같이 두는 이유다. 파일명은 ASCII를 기본으로 하고
  비ASCII 파일명 테스트는 2번 레인 하나로 격리한다.
- 줄 끝은 CRLF. 원본 배포본 `LR2files/Config/sample_*.bme`가 CRLF다. BOM은 넣지 않는다(첫 줄이 `#`로 안 시작하게 된다).

### 헤더

| 명령 | 파서 위치 | 결정 |
|---|---|---|
| `#PLAYER` | `LR2/` 전체 grep 결과 없음 | 파싱되지 않는다. 키모드는 채널에서 추론한다(`LR2_songmanage.cpp:3033` 채널 줄 판별, `3044-3058`: 기본 5, 채널 18/19 → 7, 2x 채널 → 10/14, 28/29 → 14, `.pms` 확장자 → 9(2984행)). 관례대로 SP는 `#PLAYER 1`, DP·PMS는 `#PLAYER 3`을 적는다(원본 `sample_9.pms`·`sample_10.bme`·`sample_14.bme`가 그렇다) |
| `#TITLE` `#ARTIST` `#GENRE` `#STAGEFILE` `#BANNER` | `LR2_songmanage.cpp:204-239` (`IsTextCommand`/`ParseTextCommand`) | 선곡 DB용. 플레이 파서는 무시한다 |
| `#PLAYLEVEL` `#DIFFICULTY` `#RANK` | `LR2_songmanage.cpp:3007,3010,3017`; `#RANK`는 `LR2_bmsload.cpp:2473-2485` | 전부 기록한다 |
| `#TOTAL` | `LR2_bmsload.cpp:2467-2469` | 게이지 계산용. 미기재 시 3791-3803행의 노트 수 기반 자동값이라 비교를 위해 명시한다 |
| `#BPM n` | `LR2_bmsload.cpp:2424-2462` | 초기 BPM. 120 |
| `#BPMxx n` | `2487-2495` (인덱스 4-5열, 값 7열부터) | `#BPM01 180`, `#BPM02 120` |
| `#STOPxx n` | `2496-2503` (인덱스 5-6열, 값 8열부터, `n>0`만) | `#STOP01 96`. 실시간 = n/192 × 240000/BPM (2872행) |
| `#SCROLLxx n` | `2504-2512` (인덱스 7-8열, 값 10열부터) | `7key_scroll.bms`만 사용 |
| `#BASE 62` | `2470-2472` | `7key_base62.bms`만 |
| `#LNOBJ xx` | `2464-2466`, 페어링 `2767-2778` | `7key_lnobj.bms`만 |
| `#LNTYPE` | grep 결과 없음 | 파싱되지 않는다. 아래 LN 항목 참고 |
| `#WAVxx` | `2513-2542`, 파일 탐색 `En_fileutil.cpp:734-826` | 파일명은 7열부터. 정확한 경로 → `.ogg/.wav/.flac/.mp3` 확장자 교체 → 상위 폴더 순으로 찾는다 |
| `#BMPxx` | `2543-2553`, 탐색 `En_fileutil.cpp:666-731` | BGA 설정이 켜져 있을 때만 로드한다(2543행 조건) |
| `#RANDOM` `#IF` `#ENDIF` | `2317-2331` | `#RANDOM` 직후 `ifOn=0`이라 첫 `#IF` 전 줄은 버려진다. 공통 줄은 `#RANDOM` 앞이나 마지막 `#ENDIF` 뒤에 둔다. 선곡 메타는 `#IF 1` 분기만 센다(`LR2_songmanage.cpp:2992-2997`)라 두 분기 노트 수를 같게 만들었다 |

### 객체 인덱스

- base36: `En_fileutil.cpp:552-565`, base62: `537-549`, 분기: `567-569`. base62 자릿수 순서는 `0-9`, `A-Z`(10-35), `a-z`(36-61).
- `#WAV`·`#BMP`·`#BPMxx`·`#STOPxx` 인덱스는 원문 대소문자 그대로(`fBufOrg`) 디코드된다(2375, 2396, 2490, 2498행).
- 슬롯 상한은 `SINGLESLOTS` 3844(`structure.h:26`). `zz`=3843이 마지막 유효 인덱스다.
- 공통 키음은 전부 `0x` 형태(첫 글자 `0`, 둘째 `0-9A-Z`)로 두어 두 base에서 같은 값이 된다.
- 선곡 메타의 노트 세기와 `#LNOBJ`는 base36 고정이다(`LR2_songmanage.cpp:3018-3023, 3066-3081`). base62 chart의 `a0`·`zz`도 0이 아니라 세기는 맞지만, base62 `#LNOBJ`는 선곡 메타에서 어긋난다. 그래서 `7key_lnobj.bms`는 base36이다.

### 채널

| 채널 | 파서 | 결정 |
|---|---|---|
| 01 BGM | `structure.h:104` | 0마디에 `bgm`과 `muon` 두 줄 |
| 02 마디 길이 | `LR2_bmsload.cpp:2350-2354` | 7마디 `0.75` |
| 03 BPM(16진) | `2355-2369`, `HEXcharToInt` `En_fileutil.cpp:571-583`, 적용 `2821-2826`(0 초과만) | 3마디 중간 `96`=150 |
| 04/06/07 BGA base/poor/layer | `structure.h:107-110`, soundonly 해제 `2343` | 0·2·4·6·7마디 |
| 08 `#BPMxx` | `2395-2397`, 적용 `2844-2869`(음수는 절댓값) | 4·5마디 |
| 09 `#STOPxx` | `2870-2874` | 5마디 중간 |
| `SC` `#SCROLLxx` | 판별 `2335-2341`, 상수 `structure.h:245`(2888), 적용 `2875-2895` | `7key_scroll.bms` |
| 11-15, 18, 19 / 16 | `channelConvert` `LR2_bmsload.cpp:21-298`: 16→10(scratch), 18→16, 19→17 | 7키 SP. `sample_7.bme`와 같다 |
| 21-25, 28, 29 / 26 | 26→20, 28→26, 29→27 | 14키 2P. `sample_14.bme`와 같다 |
| 11-15 / 16, 21-25 / 26 | 위와 같음 | 5키·10키. `sample_5.bme`, `sample_10.bme`와 같다 |
| 11-15, 22-25 (PMS) | isPMS: 22→16, 23→17, 24→18, 25→19 | 9키. `sample_9.pms`와 같다. `.pms` 확장자가 `is9key`를 켠다(2287-2289) |
| 51-55, 58, 59 / 56, 61-65, 68, 69 / 66 | 56→50, 58→56, 59→57, 66→60, 68→66, 69→67; PMS 62-65→56-59 | LN 채널 |
| 71-79, 91-99 등 | `channelConvert` default | 쓰지 않는다 |

### 롱노트: 채널 5x를 기본으로 선택한 이유

- `#LNTYPE`은 어디서도 읽지 않는다. 채널 5x 객체는 같은 레인에서 홀수번째가 시작, 짝수번째가 끝으로
  무조건 짝지어진다(`LR2_bmsload.cpp:2755-2766`). 이것이 BMS 사양의 `#LNTYPE 1` 의미와 같다.
- 원본 배포본의 다섯 샘플 chart 모두 LN을 채널 5x로 쓰고 `#LNTYPE`을 적지 않는다.
- 따라서 `7key_core`와 모드별 chart는 채널 5x를 쓰고, 문서 목적으로 `#LNTYPE 1`을 헤더에 적어 둔다(무시된다).
- `#LNOBJ`(2767-2778행)는 별도 경로라 `7key_lnobj.bms`로 분리해 둘의 판정이 같은지 본다.

### 파일 탐색과 대소문자

- `IsFileExist`(`En_fileutil.cpp:417-432`)는 Windows에서 `FindFirstFileA`(대소문자 무시),
  그 외에서 `std::filesystem::exists`(파일시스템에 따름)다. `case_mismatch/`는 이 차이를 드러낸다.
- 확장자 교체 폴백(`FindAltSound` 744-775행)은 스템 대소문자를 바꾸지 않으므로 대소문자 구분 FS에서는 구제되지 않는다.

### 오류 chart 근거

- 없는 파일: `FindAltSound`가 0을 돌려주고 로그만 남긴다(823행). `FindAltImage`도 0(731행).
- `#BPM 0`: `BPM_fix`·`nowBPM`이 0이 되고 STOP 실시간 계산이 `240000/nowBPM`(2677, 2872행)이라
  0 나누기가 생긴다. 실제 증상(무한대 시간, 정지, 크래시)은 실행해 봐야 안다. **미확인**.
- 0바이트: `fopen` 성공, 줄 없음. `#BPM` 없이 끝날 때 초기 BPM이 무엇으로 남는지는 추적하지 않았다. **미확인**.
- 잘린 줄: 데이터 길이가 홀수여도 `div=(len-7)/2`로 내림(2372행)이라 마지막 반쪽 객체만 버린다. 크래시 경로는 없다.

## 곡 폴더 등록

- 설정 파일은 `LR2files/Config/config.xml`이다(`LR2/Main.cpp:291`). 곡 루트는
  `<config><jukebox><path>` 요소 하나당 하나다(`LR2_configsave.cpp:28-55` 읽기, `187-191` 쓰기).
- 파일은 `encoding="shift_jis"` 헤더로 쓰인다(156행). 따라서 **등록하는 경로 자체는 ASCII**여야 한다.
  생성 결과의 루트 `<out>`(기본 `<repo>/.local/qa/synthetic`)을 등록하면 비ASCII 하위 폴더는 스캔으로 발견된다.
- 역슬래시는 슬래시로 바뀌고 끝에 구분자가 붙는다(7-26행). 수동으로 넣을 때는 아래처럼 쓴다.

```xml
<config>
  <jukebox>
    <path>C:\qa\synthetic\</path>
  </jukebox>
</config>
```

- `openlr2-config.xml`(`Main.cpp:295`)에는 곡 경로가 없다. 원본 LR2.exe 런처(설정 화면의 폴더 추가)나
  LR2Nexus 같은 외부 도구로 넣은 값도 같은 `<path>` 요소로 저장된다. 런처 UI 경로는 이 저장소에서
  확인하지 않았다. **미확인**: 런처가 비ASCII 경로를 어떻게 저장하는지.
- 폴더 스캔은 Windows API `FindFirstFileA` 기반이다(`LR2_songmanage.cpp:1360, 2018`). ANSI 코드페이지에
  없는 글자가 든 폴더명(일본어 로케일에서 한글 등)은 원본에서 목록에 안 뜰 수 있다. 그 결과 자체를 I18N-01 기록으로 남긴다.
- 폴더 hash는 `AssignCRC32`가 경로를 CP932로 바꿔 계산한다(`En_fileutil.cpp:592-596`). 한글 경로는 변환이
  실패하거나 손실되므로 DB 재조회 일치 여부를 따로 본다. **미확인**.

## 스킨 해상도 변형

원본 Theme 스킨은 재배포 대상이 아니므로 저장소에 넣지 않고, 테스터의 LR2beta3 압축 해제 폴더에서 변형을 만든다.

```bash
python3 docs/preparation/qa/make_skin_resolution_variants.py --lr2-root /path/to/LR2beta3
# 옵션: --full-copy (이미지·csv까지 복사), --include-before-information, --force, --source-theme LR2
```

| 폴더 | 삽입 줄 | 파서 기대 동작 (`LR2_skinmanage.cpp`) |
|---|---|---|
| `LR2_res0` | `#RESOLUTION,0` | 640×480 (258-261행) |
| `LR2_res1` | `#RESOLUTION,1` | 1280×720 (262-265) |
| `LR2_res2` | `#RESOLUTION,2` | 1920×1080 (266-269) |
| `LR2_res3` | `#RESOLUTION,3` | 3840×2160 (270-273) |
| `LR2_res_bad` | `#RESOLUTION,abc` | `SplitCSV`가 `atol("abc")`=0으로 읽어(`En_fileutil.cpp:478-520`) case 0과 같아진다. 경고 없이 640×480이면 "조용한 성공"이므로 ACCEPTANCE 위반 후보 |
| `LR2_res9` | `#RESOLUTION,9` | default 분기: targetX=max(9,640)=640, targetY=max(0,480)=480 (274-277) |
| `LR2_res_before` (옵션) | `#INFORMATION` **앞**에 `#RESOLUTION,2` | `Data[Count-1]`에 쓰는데 Count가 0일 수 있다(258행 TOFIX). 크래시 가능. `--include-before-information`을 줄 때만 생성 |

- 스킨 목록은 `LR2files/Theme/` 아래를 재귀 스캔해 `.lr2skin`/`.lr2ss`만 읽는다(104, 386-404행).
  그래서 변형 폴더를 원본 옆에 두면 자동으로 뜬다.
- 적용은 `LR2_skinload.cpp:1903-1910`: `hasResolutionTag`면 스킨 값으로 `Resize`, 아니면 전역 설정값.
- `#INFORMATION`의 제목 필드(3번째 CSV 열)에 ` [resN]`을 덧붙여 스킨 선택 화면에서 구분한다.
  경로 필드(썸네일·`#INCLUDE`·`#SRC_IMAGE`)는 `LR2files\Theme\LR2\...` 루트 상대 경로라 복사본이 원본 자산을 그대로 쓴다.
  기본 모드는 `.lr2skin`만 복사한다(원본 Theme/LR2는 144파일 58MB).
- 파일은 바이트 단위로 편집해 CP932 주석과 CRLF/LF를 보존한다. 원본 폴더는 수정하지 않는다.
  기존 `#RESOLUTION` 줄이 있으면 지우고 새 줄 하나만 남긴다.
- 변경 내역은 `<lr2-root>/LR2files/Theme/LR2_res_variants.json`에 스킨별 원본/결과 SHA-256, 삽입 줄 번호, 제목 변경으로 남긴다.
- `--force`는 이번 실행이 만들 폴더만 지운다. 이전에 `--include-before-information`으로 만든 `LR2_res_before`는 옵션 없이 재실행하면 남는다.
- 스크립트는 `--lr2-root`가 이 저장소 안이면 거부한다. 검증은 scratch의 가짜 트리(CRLF·CP932 주석 스킨, LF 스킨, `#RESOLUTION,1`이 이미 있는 스킨, `#INFORMATION` 없는 스킨)로만 했다. 실제 LR2beta3 트리에는 실행하지 않았다.

## 다루지 않는 것

- 스킨 자산: 생성하지 않는다. `#RESOLUTION` 변형은 위 스크립트로 테스터 로컬에서 만든다.
- 리플레이 파일: 생성하지 않는다. 원본/포크 각각에서 자동 플레이 또는 실제 플레이로 만든 리플레이를 같은 chart hash와 함께 보관한다.
- 코스·NONSTOP·EXPERT 폴더(`folderinfo.txt`, 코스 정의): 없음.
- 숨김 노트(3x/4x), 지뢰(Dx), `#FP/DSC`, `#EXBPM` 이외의 확장 채널: 없음.
- OGG/FLAC/MP3 키음, PNG/JPG BGA, 동영상 BGA: WAV·BMP만 생성한다. 확장자 폴백 경로는 `missing_refs`로 간접 검사한다.
- 읽기 전용 폴더: 생성기는 권한을 바꾸지 않는다. OS에서 수동 설정한다.
- 점수 DB·`config.xml` 자체: 만들지 않는다. "빈 DB"는 테스터가 새 LR2files로 시작해 만든다.

## 미확인 항목

- `#BPM 0`, 0바이트 chart의 실제 엔진 증상. 소스상 0 나누기 경로만 확인했다.
- 원본 LR2.exe 런처의 폴더 등록 UI와 비ASCII 경로 저장 방식.
- 한글 폴더 경로의 `AssignCRC32` 결과와 DB 재조회 일치 여부.
- 비ASCII 파일명 키음(`鍵音02.wav`, `건반02.wav`)의 Windows 원본 동작. 소스는 CP932→UTF-8 변환 후 `fopen`류로 열므로 Windows ANSI 경로에서 실패할 수 있다.
- macOS에서 이 자산을 실제 엔진에 넣어 보지 않았다. 검증 범위는 아래와 같다.

## 이번 생성기의 검증 범위

실행한 것(macOS, Python 3.15, `python3 -I`):

- 생성 결과 127파일 전부: manifest의 크기·SHA-256 일치, WAV는 `wave` 모듈로 열어 모노·16비트·44.1k/22.05k 확인,
  BMP는 `BM` 시그니처·파일 크기·오프셋 54·헤더 40·24bpp·BI_RGB·행 바이트×높이 일치 확인,
  chart는 선언한 인코딩(UTF-8 또는 CP932)으로 디코드 확인, CP932 판이 UTF-8로는 디코드되지 않음 확인.
- 같은 seed 재실행 두 번: manifest 완전 동일. seed 7: WAV/BMP 20개만 달라지고 chart 텍스트는 동일.
- (1.1.0) manifest를 바이트로 써서 OS 개행 변환 없음(LF만) 확인. 1.0.0과 생성 파일 127개의 SHA-256 동일, manifest의
  `expected_notes`·`generator_version`만 바뀜. 노트 수 셈법 정정은 PR #1 리뷰 지적 반영
- 기존 출력에 `--force` 없이 실행 → 종료 2. `--force` 실행 → 생성 폴더·manifest만 교체, 다른 파일 유지.
- 기본 경로(`<repo>/.local/qa/synthetic`) 실행 후 `git status --short`에 `.local` 아래 항목 없음.
- 정적 참조 검사: 모든 `#xxxyy:` 줄 데이터 길이 짝수, 채널 08/09/SC/04/06/07/키음 객체가 전부 정의됨,
  참조 파일 존재. 예외는 의도한 `broken/` 두 chart뿐.

실행하지 않은 것: 원본 LR2·OpenLR2에 실제 로드, Windows/Linux 파일시스템 동작, 스킨 변형의 실제 LR2beta3 적용.
