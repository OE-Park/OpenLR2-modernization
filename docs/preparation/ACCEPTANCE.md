# 플랫폼·누수·4K 인수 기준 초안

“완전 지원”은 아래 합의된 OS·장치·시나리오 범위의 통과를 뜻하도록 구체화한다.
현재 검증 실적이 아니라 앞으로 실행할 기준이다. 지원 OS 최소 버전·장치 목록은 기준 실행 때 기록한다.

## 대상 행렬

| 대상 | 필수 산출물 | 필수 실행 환경 | 별도 보조 결과 |
|---|---|---|---|
| Windows 11 x64 | PE x64 앱·로드 DLL | Windows 11 x64 실기기, GPU/오디오/HID 모델 기록 | x86 비교본 |
| Windows on ARM | PE ARM64 앱·로드 DLL | Windows 11 ARM64 실기기 | x64/x86 에뮬레이션은 별도 결과 |
| macOS arm64 | arm64 Mach-O 앱·로드 dylib | Apple Silicon macOS 실기기 | Rosetta/Wine 결과는 별도 결과 |

컴파일러 호스트·타깃 아키텍처·동적 의존성을 각각 기록한다. x64 DLL을 ARM64 앱 안에 로드하는 구성은 네이티브 완료로 세지 않는다.
빌드 CI와 실제 입력·오디오·표시 검증은 별도 열로 관리한다.

## 공통 기능

- 새 테스트 폴더와 빈 점수 DB 사용. 기존 점수 DB는 복사본으로 migration 테스트, 원본 해시 보존.
- 5/7/9/10/14키 중 제품에서 제공하는 모드, scratch·동시 입력·롱노트·BPM/STOP·리플레이를 합성 입력/재생으로 비교.
- 같은 chart·옵션·random seed·입력 시계 조건에서 원본/포크 판정과 점수 차이를 설명. 의도하지 않은 변화는 회귀다.
- UTF-8·일본어/한국어 파일명·공백 경로·대소문자 차이·없는 파일·읽기 전용 폴더 검사.
- 키음·preview·BGA·빠른 재시작·NONSTOP·결과→선곡·종료 검사. upstream README의 NONSTOP 점수 저장 known issue는 별도 추적.
- 키보드, 지원 BMS 컨트롤러, analog scratch, hot-plug, 포커스 이탈/복귀 검사. 장치 모델·펌웨어·모드·권한 기록.
- ASIO 등 특정 플랫폼 전용 기능은 해당 플랫폼의 가용성·대체 경로·미지원 상태를 명시. 지원하지 않는 설정은 조용히 성공으로 처리하지 않는다.
- Windows ASIO: 실제 ASIO 장치에서 `output=2` 설정으로 기동·플레이·종료, 드라이버 선택 반영, 장치 없음/점유 시 폴백 동작과 로그를 확인한다. 지연·드롭은 WASAPI와 같은 조건에서 비교 기록한다.
- 다국어: 일본어·한국어·영어·혼합 파일명과 곡 메타, 공백·긴 경로, IME 검색 입력, 스킨 폰트의 CJK 렌더를 세 플랫폼에서 확인한다. 기존 DB의 CP932 기반 해시와 새 입력의 일치·불일치를 설명한다.
- 런처: 설정 변경이 `config.xml`/`openlr2-config.xml`에 원본 호환 형식으로 저장되고 엔진이 그대로 읽는지, 원본 LR2와 OpenLR2 양쪽 기동이 되는지 확인한다.
- 모든 native plugin/IR module은 ABI·아키텍처·오류 처리를 검사하고, 비호환 모듈은 명확한 진단 제공.
- IR 제외 빌드(macOS 전체): 레거시 LR2IR·CustomIR 송수신과 `LR2files/CustomIRs/` 모듈 로드가 일어나지 않음을 네트워크·파일 접근 기록으로 확인한다. 랭킹 표시 요소는 IR 없음을 명확히 보이고 조용히 빈 값으로 성공 처리하지 않는다.

## 메모리 기준

1. 원본, 수정 전 포크, 수정 후 포크를 같은 장비·chart·skin·옵션으로 분리 측정한다.
2. 워밍업 10회 후 `선곡→플레이→결과→선곡` 100회, 스킨 프리뷰/변경 100회, 빠른 재시작/취소 100회를 각각 실행한다.
3. Windows private committed bytes·working set, macOS footprint/RSS, live heap bytes·allocation stack, GPU 자원 수/VRAM을 구분해 기록한다.
4. 매 회 동일 대기 지점에서 측정하고 idle 대조군·메모리 기울기·peak·종료 후 미해제 stack을 남긴다. 단순 RSS peak 감소는 누수 제거의 근거가 아니다.
5. **수정한 소유권 경로의 확정 누수 0, double-free/use-after-free 0, 종료/취소 callback의 해제 후 접근 0**을 요구한다.
6. 정상 캐시는 소유자·최대 용량·eviction 조건을 명세하고, 워밍업 이후 live object 수가 계속 증가하지 않아야 한다. RSS 허용 폭은 baseline/idle 변동을 보고 수정 전에 수치로 고정한다.
7. Windows ASan은 주소 오류 검출에 사용하고 leak coverage는 별도 도구로 확보한다. macOS Instruments Allocations/Leaks 등 실제 지원 도구를 확인한다.

측정 CSV에는 timestamp, build SHA, scenario, iteration, checkpoint, process identity, memory metric/unit, live resource count, result를 남긴다.
기준 숫자를 얻기 전 메모리 개선율·합격을 만들어 적지 않는다.

## 4K 기준

- 필수 출력: 3840×2160. SD 640×480·HD 1280×720·FHD 1920×1080 회귀 포함.
- 전역 설정과 `#RESOLUTION,0/1/2/3`, custom width/height의 우선순위·유효 범위·실패 처리 검증. `#INFORMATION` 전 `#RESOLUTION`, 음수·초과치도 검사.
- 스킨 논리 좌표, 창 논리 크기, drawable/framebuffer 픽셀 크기를 별도로 기록. SD 스킨 확대와 실제 UHD 스킨을 구분한다.
- Windows DPI 100/150/200%, macOS Retina 배율, 서로 다른 DPI 모니터 이동, 전체화면/창모드/F4/Alt+Tab·resize·suspend/restore 검사.
- 화면별(선곡·결정·플레이·결과·코스 결과·키설정·스킨 선택) clipping·글자·마우스 hit-test·aspect/stretch·스크린샷 크기 확인.
- UHD BGA/texture 실패·VRAM 부족 시 명확한 진단과 자원 정리. 긴 전환 반복에서 handle/texture 누적 없음.
- 필수 성능 기준 제안: 명시한 기준 장비의 4K 60Hz에서 steady-state p99 CPU/GPU frame time 16.67ms 이내. 120/144Hz는 별도 확장 목표로 측정한다.
- 오디오 underrun, 입력 event 유실, 판정·오디오 지연을 baseline과 비교. 물리 지연은 loopback/실측이 필요하며 소스·소프트웨어 timestamp만으로 단정하지 않는다.

## 결과 파일

`/.local/evidence/<build>/<platform>/<scenario>/`에 실행 manifest, raw metrics, 로그, 캡처를 보관한다.
공유 가능한 짧은 결과 문서에는 환경·커밋·입력 hash·실행 명령·결과·미검증 항목과 근거 경로를 남긴다.
개인 점수·상용/사용자 자산·분석 DB를 저장소나 CI artifact에 올리지 않는다.
