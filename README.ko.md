# IYAGI 5.3 SSH 래퍼 (DOSBox)

구형 DOS 통신 프로그램 **IYAGI 5.3**를 DOSBox-Staging + 로컬 Go 브리지로 감싸서, 현대 환경에서 **SSH**로 사용할 수 있게 만든 프로젝트입니다.

지원 대상:
- 로컬 Linux 실행 (`tools/run-dosbox.sh`, `tools/run-direct.sh`)
- Linux AppImage 패키징
- Windows 포터블/인스톨러 흐름
- macOS 앱 번들/DMG 흐름

---

## 이 프로젝트가 하는 일

- IYAGI 5.3를 DOSBox 안에서 실행
- IYAGI COM 포트 트래픽을 로컬 브리지(모뎀형 AT 파서)로 연결
- `ATDT...`를 SSH 연결 시도로 변환
- SSH-BBS 스타일 로그인(`SSH_AUTH_MODE=bbs`) 또는 키 기반 모드(`SSH_AUTH_MODE=key`) 지원
- IYAGI와 UTF-8 서버 간 한글 인코딩 변환
- 모뎀 다이얼/통화중/벨소리/연결 사운드 재생

---

## 런타임 구조

```text
IYAGI (DOS 앱)
  -> DOSBox-Staging의 COM4
  -> nullmodem tcp 127.0.0.1:<bridge_port>
  -> bridge (Go)
  -> ssh 클라이언트 프로세스
  -> 대상 SSH 서버 / SSH-BBS
```

사용자 입장에서는 기존 다이얼업 터미널처럼 동작합니다:
- `AT` / `ATDT...` / `ATH` / `ATO` 스타일
- 모뎀 응답 문자열 (`OK`, `CONNECT`, `NO CARRIER` 등)

---

## 빠른 시작 (Linux 로컬)

저장소 루트에서:

```bash
task deps
./tools/run-dosbox.sh
```

`task deps`가 하는 일:
- `software/iyagi53dos.zip` 압축 해제 (이미 풀려 있으면 건너뜀)
- `third_party/dosbox-staging`에 portable DOSBox-Staging 다운로드

첫 실행 시 생성/사용:
- `iyagi-data/.env`
- `iyagi-data/app/IYAGI`
- `iyagi-data/downloads`

---

## ATDT 다이얼 동작

IYAGI 터미널에서:

- `ATDT<host>:<port>` -> 해당 타깃으로 직접 접속
- `ATDT<host>` -> SSH 포트 22 기본값 사용
- `ATDT` (빈 타깃) -> 톤 재생 후 `NO CARRIER`
- `ATDT;` -> 톤 재생 후 `OK`

브리지가 ATDT 문자열을 직접 파싱해 대상 SSH로 연결 시도합니다.

---

## 설정

기본 템플릿:
- `resources/common/.env.example`

로컬 런타임 설정:
- `iyagi-data/.env`

### 주요 환경 변수

- `SSH_AUTH_MODE`:
  - `bbs` (기본): 로컬 키 필요 없음
  - `key`: `iyagi-data/keys`의 로컬 키 사용
- `BRIDGE_PORT`: 로컬 브리지 포트 (`auto` 지원)
- `BRIDGE_CONNECT_TIMEOUT_SEC`: 타깃 접속 시도 타임아웃
- `BRIDGE_BUSY_REPEAT`, `BRIDGE_BUSY_GAP_MS`
- `BRIDGE_DTMF_GAP_MS`
- `BRIDGE_POST_DTMF_DELAY_MS`
- `BRIDGE_CLIENT_ENCODING`, `BRIDGE_SERVER_ENCODING`
- `BRIDGE_SERVER_REPAIR_MOJIBAKE`
- `BRIDGE_DEBUG`

DOSBox 타이밍/화면:
- `DOSBOX_CPU_CORE` (기본 `simple`)
- `DOSBOX_CPU_CPUTYPE` (기본 `386`)
- `DOSBOX_CPU_CYCLES` (Staging 경로에서는 숫자 사용)
- `DOSBOX_VIDEO_BACKEND` (`auto|x11|wayland`)
- `DOSBOX_WAYLAND_STRICT`

스캔라인 셰이더 토글 (DOSBox-Staging):
- `DOSBOX_SCANLINES=0|1`
- `DOSBOX_GLSHADER` (예: `crt/vga-1080p`)
- `DOSBOX_SCANLINE_WINDOWRES` (예: `1280x960`)

---

## 스캔라인 프리셋 (DOSBox-Staging)

`DOSBOX_SCANLINES=1`이면 Staging이 OpenGL 셰이더 모드로 전환됩니다.

권장 프리셋:
- Sharp: `crt/vga-1080p-fake-double-scan`
- Balanced: `crt/vga-1080p`
- Soft: `crt/composite-1080p`

사용 가능한 셰이더 목록:

```bash
third_party/dosbox-staging/unpacked/dosbox --list-glshaders
```

---

## 마우스/네트워크/MIDI 기본값

터미널 용도에 맞춰 아래 기본값으로 튜닝되어 있습니다:

- DOS 게스트 마우스 입력 비활성화:
  - `mouse_capture=nomouse`
  - `dos_mouse_driver=false`
- DOSBox ethernet/slirp 비활성화:
  - `[ethernet] ne2000=false`
- MIDI 출력 비활성화:
  - `mididevice=none`

불필요한 경고/노이즈를 줄이고 IYAGI 입력 간섭을 줄이기 위한 설정입니다.

---

## 빌드 출력

### Linux AppImage

```bash
bash tools/build-linux.sh
```

출력:
- `dist/IYAGI-linux-x86_64.AppImage`

### 빌드된 AppImage 로컬 실행

```bash
./tools/run-appimage.sh
```

---

## 런처 스크립트

로컬:
- `tools/run-dosbox.sh` (portable DOSBox-Staging 중심)
- `tools/run-direct.sh` (직접 실행 스크립트, fallback 지원)

패키지 런처:
- Linux AppImage: `resources/linux/launch.sh`
- macOS: `resources/macos/launcher`
- Windows: `resources/windows/launch.bat`

플랫폼 간 런처 동작은 의도적으로 최대한 동일하게 유지합니다.

---

## Taskfile

`Taskfile.yml` 작업:

- `task deps` (IYAGI 압축 해제 + DOSBox 다운로드)
- `task iyagi:extract`
- `task dosbox:download`
- `task keys:generate`
- `task bridge:embed-sounds`
- `task bridge:build`

---

## 데이터 디렉터리

### 로컬 스크립트 모드
- 루트: `iyagi-data/`
- 앱 파일: `iyagi-data/app/IYAGI`
- 다운로드: `iyagi-data/downloads`
- 환경 파일: `iyagi-data/.env`

### AppImage 모드 (기본)
- 설정: `${XDG_CONFIG_HOME:-~/.config}/iyagi-terminal`
- 데이터: `${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal`

다음 변수로 둘 다 오버라이드 가능:
- `USER_DATA_ROOT`

---

## 문제 해결

- 커서가 너무 빠르게 깜빡임:
  - `DOSBOX_CPU_CYCLES`를 낮춰 조정 (예: 1200 -> 1000 -> 800)
- 셰이더 켰더니 창 안에서 화면이 작아 보임:
  - `DOSBOX_SCANLINE_WINDOWRES=1280x960` 사용 (640x480 기준 2x 느낌)
- 다이얼 톤이 너무 빠름:
  - `BRIDGE_DTMF_GAP_MS` 증가
- 다이얼 후 대기 시간을 더 주고 싶음:
  - `BRIDGE_POST_DTMF_DELAY_MS` 증가

---

## 법적 참고

IYAGI는 오픈소스가 아닌 프리웨어입니다.  
배포 채널에 따라 재배포 권리를 반드시 확인하세요.

