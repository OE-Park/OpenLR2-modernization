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

현재 작업은 조사·준비다. 제품 코드·`CMakeLists.txt`·CI workflow는 수정하지 않았고(`CMakePresets.json`에 VS 2026 preset만 추가), 세 플랫폼 실행 지원이나 누수 개선을 완료하지 않았다.
