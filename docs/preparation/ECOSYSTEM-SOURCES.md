# BMS 생태계 원천 자료

조사일 2026-10-27. 웹 검색·페이지 열람으로 모은 목록이다. 공식 표준 기구는 없다. 사실상 기준은 원본 동작·커뮤니티 문서·주요 구현 소스다.
LR2 동작의 1차 근거는 웹 자료가 아니라 upstream 브랜치 `LR2Beta3-v100201`(원본 디컴파일 소스)과 원본 바이너리 비교다. 웹 자료는 그 결과를 해석하고 커뮤니티 기대치를 확인하는 데 쓴다.

열람 범위 표기: **열람** = 페이지 내용을 직접 읽음, **검색** = 검색 결과 요약으로만 확인.

## 1. 포맷 명세

| 자료 | 다루는 것 | 확인 | 관련 작업 |
|---|---|---|---|
| [BMS command memo (hitkey)](https://hitkey.nekokan.dyndns.info/cmds.htm) | BMS/BME/BML/PMS 헤더·채널·`#RANDOM`/`#SWITCH`. 플레이어별 해석 차이에 LR2 항목 다수(`#PLAYER` 무시, `#000` 앞 빈 마디, 지뢰 채널 중복, `#RANK`별 판정 폭). 2014-07-11 갱신, 기계번역 기반 비공식 메모라고 명시 | 열람(앞 1/3) | QA-01, 파서 회귀 |
| [bmson-spec](https://bmson-spec.readthedocs.io/en/latest/) | bmson(JSON 차트) 명세 | 검색 | 범위 밖(OpenLR2는 bmson 미지원) |
| [BMS #TOTAL Calculator (hitkey)](https://hitkey.nekokan.dyndns.info/total.htm) | `#TOTAL` 미지정 시 기대값 | 검색(목록) | QA-01 게이지 |

## 2. LR2 판정·게이지 수치

| 자료 | 다루는 것 | 확인 | 관련 작업 |
|---|---|---|---|
| [IIDX / LR2 / beatoraja differences (iidx.org)](https://iidx.org/misc/iidx_lr2_beatoraja_diff) | LR2 판정 폭(EASY PG±21·GR±60·GD±120·BD±200, NORMAL ±18/40/100/200, HARD ±15/30/60/200, VERY HARD ±8/24/40/200, 공POOR +1000), 게이지 증감식, HARD 피해 감소 표, 공POOR는 노트 앞에서만. LR2 LN 릴리스 폭은 없음 | 열람 | QA-01, 판정 회귀 기준 |
| [LR2 Timing Window (hitkey 일기 2015-01-19)](https://hitkey.nekokan.dyndns.info/diary1501.php#D150119) | LR2 판정 폭 실측 글. 위 iidx.org가 인용 | 검색(목록) | QA-01 |
| [LR2oraja (wcko87)](https://github.com/wcko87/lr2oraja) | beatoraja에 LR2 판정·게이지를 이식한 구현. HARD는 2% 미만에서 실패 등 세부 | 검색 | 수치 교차 확인용 구현 |
| [beatoraja/LR2 仕様比較 (ralba-gear)](https://ralba-gear.hateblo.jp/entry/2023/11/06/141139) | 9key(PMS) 기준 판정·게이지·콤보·공POOR 차이 | 열람 | QA-01 PMS |

수치가 자료마다 조금씩 다르다(예: HARD 피해 감소 시작점 30% vs 32%). 원본 소스·바이너리 측정으로 확정한다.

## 3. 스킨

| 자료 | 다루는 것 | 확인 | 관련 작업 |
|---|---|---|---|
| [LR2SkinHELP 第九版 (right-stick)](http://right-stick.sub.jp/lr2skinhelp.html) | LR2 스킨 CSV 변수 레퍼런스. RED. 스킨 CSV 仕様書(第八版)의 후속으로 보인다 | 제목만 확인(프레임 구조라 본문 미수집) | UHD-01, 스킨 회귀 |
| [LR2のスキンについてのメモ (Lmac)](https://lmac.hatenablog.com/entry/2016/01/12/193827) | `.lr2skin`과 CSV 관계, `#IMAGE`·`#SRC_IMAGE` 등 기본 명령, RED. 仕様書 언급 | 검색 | UHD-01 |
| `new_command(skin).md`(저장소) | OpenLR2가 추가한 스킨 명령(`#RESOLUTION` 등) | 저장소 | UHD-01 |

## 4. 난이도표·코스

| 자료 | 다루는 것 | 확인 | 관련 작업 |
|---|---|---|---|
| [DARKSABUN's List of Tables](https://darksabun.github.io/table/tablelist.html) | 난이도표 색인 | 검색(목록) | 테스트 자료 선정 |
| [Stella / Satellite](https://stellabms.xyz/) | 현역 주요 표, 표 변경 투표 | 검색(목록) | — |
| [bms-table (Rust crate 문서)](https://docs.rs/bms-table/latest/bms_table/), [bmstable (Go)](https://pkg.go.dev/github.com/Catizard/bmstable) | 표 형식: HTML `<meta name="bmstable">` → header JSON(`name`·`symbol`·`data_url`·`course`·`level_order`) → data JSON(`level`·`md5`·`sha256`·`url`·`url_diff`). 공개 명세 문서는 찾지 못했고 구현이 사실상 명세 | 검색 | 표 지원을 넣을 경우 |

## 5. IR·점수 추적

| 자료 | 다루는 것 | 확인 | 관련 작업 |
|---|---|---|---|
| [Bokutachi](https://bokutachi.xyz) / [BokutachiIR_OpenLR2](https://github.com/marysiamzawka/BokutachiIR_OpenLR2) | LR2·LR2oraja·OpenLR2(CustomIR) 점수 추적 | 검색 | IR-01 |
| [beatoraja Discussion #668](https://github.com/exch-bms2/beatoraja/discussions/668) | 판정 체계가 다른 점수의 혼합 반대 의견 | 열람 | IR-01 |
| [beatoraja 非公式Q&A](https://mirai-yokohama.sakura.ne.jp/bms/beatoraja/) | 비공식 빌드 IR 접속 불가, 오디오 출력별 지연 | 열람 | IR-01, ASIO-01 |
| [Cinnamon](https://cinnamon.link), [MochaIR](https://mocha-repository.info/) | beatoraja 계열 IR | 검색(목록) | 참고 |

## 6. 커뮤니티 관례 (암묵적 규칙)

| 자료 | 다루는 것 | 확인 |
|---|---|---|
| [BOF 규칙 (bmsoffighters.net, 예: BOF22)](https://bmsoffighters.net/bof22/rule.html) | 이벤트 출품 규정: 키음 없는 BMS 금지(BOF2012), 공개 시점, 差分 패키지 배포 제한. 연도마다 다르다 | 검색 |
| [BMS用語集 (BMSまとめ@wiki)](https://w.atwiki.jp/laser_bm/pages/69.html), [BMS Terminology (keysounds)](http://news.keysounds.net/terminology) | 용어: 差分(sabun), 発狂, 段位 등 | 검색 |
| [無難な譜面の作り方](http://yaruki0.sakura.ne.jp/bms/column/), [BMS Production Checklist](https://wcko87.github.io/bms-checklist/) | 차트 제작 관례 | 검색 |
| [BMS Community Resources](https://bms-community.github.io/resources/) | 플레이어·표·IR·스킨·이벤트 패키지 종합 색인. 1,300일 이상 된 항목 포함 | 열람 |

## 7. 커뮤니티 허브

- [BMS Community Discord](https://discord.gg/Q4vKF8T), [BMS Server JAPAN](https://discord.gg/rSRVKYZ), [K-BMS](https://k-bms.com/), [r/lunaticrave2](https://www.reddit.com/r/lunaticrave2/)
- [BMSまとめ @wiki LunaticRave2](https://w.atwiki.jp/laser_bm/pages/81.html): OpenLR2 언급 있음
- [LR2 unofficial site](https://lr2.sakura.ne.jp/): LR2IR 종료 공지 반영

## 8. 참고 구현 (LR2 호환을 목표로 한 다른 플레이어)

라이선스는 확인하지 않았다. 코드 반입 전 각 저장소에서 확인한다.

- [Lunatic Vibes](https://github.com/m8nscape/lunaticvibes)(개발 중단) / [Lunatic Vibes F](https://github.com/chown2/lunaticvibesf): LR2 스킨 지원 LR2 계열 플레이어
- [LR2oraja ~Endless Dream~](https://github.com/seraxis/lr2oraja-endlessdream): LR2 판정·게이지 beatoraja 포크
- [beatoraja 소스](https://github.com/exch-bms2/beatoraja): `JudgeProperty.java`·`GaugeProperty.java`에 판정·게이지 표

## 9. 개발 요구로 옮길 관례

### 9.1 BOF(THE BMS OF FIGHTERS) 관련 예의·규칙

근거: [BOF22 Rule](https://bmsoffighters.net/bof22/rule.html)(열람). 연도마다 바뀌므로 해당 회차 규칙을 다시 본다.

- 출품 전제 플레이어 = beatoraja(Mocha-Repository판). LR2 언급 없음 → BOF 출품작이 OpenLR2에서 안 돌아도 출품 규정 위반 아님
- 지정 플레이어(beatoraja)에서 정상 재생되는데 다른 플레이어 기준으로 "재생 불가" 보고 금지 → OpenLR2 호환 문제는 OpenLR2 쪽 이슈로 처리, 제작자에게 버그 보고 금지
- 평가는 bms/bmson으로 실제 플레이한 것만. 영상·음원만 보고 평가 금지
- 일제 공개 전: 보면 전체 영상·보면 이미지 공개 금지, 웹 플레이어(bemuse 등) 선공개 금지. FINAL STRIKER는 wip·demo 포함 공개·공유 전면 금지
- 출품 조건: 상업 음악게임 음성·화상·영상·에셋 사용 즉시 실격, 허락 없는 소재·보면 사용 실격, 키음 무음률 8% 초과는 재생 불가 취급, `#MIDIFILE` 정의는 재생 불가 취급
- 파일명은 반각 영숫자 권장, 압축은 Zip/Rar/7z

OpenLR2에 미치는 것:
- QA-01·I18N-01 회귀 자료로 BOF 패키지 사용 가능. 실패는 OpenLR2 결함으로 기록
- 보면 미리보기·녹화·스크린샷 기능이 공개 금지 기간 규정을 깨는 용도로 쓰이지 않도록 기본값·안내 검토(MP3/녹화 기능은 이미 존재)

### 9.2 상용 게임 패턴 검사 (원본 LR2 동작)

원본 LR2에 이미 있는 검사다. 소스 근거(정적 조사, 실행 미확인):

- 판정: 키음 하나라도 길이 60,000 ms 초과 → `flag_longsound = 1`(`LR2/LR2_bmsload.cpp:691`). 노트 0개 → `flag_0note`(`:702`)
- 효과
  - IR 등록 거부 "この曲はIRに登録できません"(`LR2/LR2_statplay.cpp:685`, `:1022`), 코스 IR 거부 "このコースはIRに登録できません"(`LR2/Scene13_Courseresult.cpp:110`)
  - 녹화 모드·MP3 만들기 차단 "規約違反のbmsの可能性があるので、この機能は利用できません。"(`LR2/Scene04_Play.cpp:1957`, `LR2/LR2_makemp3.cpp:96`)
  - IR 상태 코드 `-2: bansong`(`LR2/structure.h:1581`)
- 의도: 상용 게임 음원을 통째로 BGM으로 넣은 변환 BMS 차단. 길이는 저작권 판정 근거가 아니라 신호일 뿐이라는 지적도 있다([tapestry issue #43](https://github.com/shuymn/tapestry/issues/43), 2026-10-26, 열람. MochaIR·rianIR은 정책·모더레이션으로 금지, 수치 기준 미확인)
- **OpenLR2 공백**: CustomIR 전송 `BeginResultIr`는 리플레이 여부(`replay.status != 2`)만 보고 호출된다(`LR2/Scene05_Result.cpp:10`, `LR2/Scene13_Courseresult.cpp:173`). `flag_longsound`·`flag_0note`를 확인하지 않고 `IRScoreV1`에도 그 값이 없다. 원본 LR2가 거부하는 차트 점수가 CustomIR 모듈로 전달된다. 모듈·서버 쪽 필터 여부 미확인 → IR-01에서 처리

### 9.3 인터넷 랭킹 주의점

- 원본 LR2 클라이언트 규칙(소스): 위 long sound·0 note 거부, 단독 플레이 기록 없는 곡은 등록 안 함 "単体でプレイしたことの無い曲はIRに登録されません"(`LR2/LR2_statplay.cpp:688`), 외부 starter 기동(`is_starter`) 시 등록 안 함
- 판정·게이지 체계가 다른 점수는 섞지 않는다: beatoraja 메인테이너 "다른 무대 비교는 경쟁적 의미가 작다"([Discussion #668](https://github.com/exch-bms2/beatoraja/discussions/668), 열람)
- IR 운영자는 클라이언트 빌드 단위로 접속 통제: 비공식 빌드(LR2oraja 등)는 beatoraja IR 접속 불가([非公式Q&A](https://mirai-yokohama.sakura.ne.jp/bms/beatoraja/), 열람)
- 부정 점수 필터 사례: Stairway의 nazoIR 집계는 RHS 1.0 미만·부정 ID·판정 합계가 총 노트의 90% 이하인 기록 제외([Stairway FAQ](https://stairway.sakura.ne.jp/bms/lr2normal2/?contents=faq), 검색)
- LR2IR 운영자 공지: 제3자 삭제 대책으로 점수·플레이어 데이터 삭제 금지([kenjidct, X](https://x.com/kenjidct/status/631097647420436480), 검색). LR2IR은 2026-05-31 종료
- OpenLR2가 CustomIR로 보내는 값: 곡 해시·판정·게이지 옵션·랜덤·assist·autokey·재생 속도 배율(`freqSpeedMultiplier`) 등(`LR2/LR2_customir_api.h`). 서버가 필터할 재료는 있음. 오디오 백엔드·플랫폼은 없음
- 이 프로젝트 결정: macOS 빌드 IR 제거([설계 초안](../superpowers/specs/2026-10-27-platform-modernization-design.md) IR 행)

## 못 찾은 것

- LR2 스킨 CSV 仕様書(RED. 第八版) 원문: 옛 geocities 경로라 열람 불가로 보인다
- 난이도표 형식의 공식 명세 문서
- Bokutachi의 클라이언트 허용 정책 문서
- 종료 전 LR2IR 이용 규약 원문(Internet Archive 확인 필요)
- BOF 기간 중 플레이어 쪽 방송·점수 공개 예의를 명문화한 문서(규칙 페이지는 제작자·평가자 중심)
