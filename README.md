# jtag-protocol

IEEE 1149.1-2013 JTAG TAP 컨트롤러를 Verilog-2001로 설계하고, 45nm 표준셀(Cadence GPDK045 기반 gsclib045)로 합성 → P&R → post-route GLS까지 마친 프로젝트다. 이후 Boundary Scan과 RISC-V Debug(JTAG-DTM + 최소 Debug Module)로 확장한다.

## 진행 단계

| 단계 | 내용 | 상태 |
|---|---|---|
| 1단계 | TAP 컨트롤러: 16상태 FSM, 5비트 IR, BYPASS, IDCODE | **완료** (LVS 제외, 아래 참고) |
| 2단계 | Boundary Scan: BSR, SAMPLE/PRELOAD/EXTEST, BSDL | 예정 |
| 3단계 | RISC-V Debug Spec JTAG-DTM(dtmcs/dmi) + 최소 DM, OpenOCD/GDB 연동 | 예정 |

## 1단계 설계 요약

`rtl/jtag_tap.v` (합성 top은 이를 감싸는 `rtl/kh_jtag_top.v`)

- **포트:** `tck`, `tms`, `tdi`, `trst_n`, `tdo`, `tdo_oe`
- **FSM:** IEEE 1149.1 Fig. 6-1의 16상태, TCK 상승 엣지에서 TMS로 전이
- **IR:** 5비트. Capture-IR에서 `00001` 로드, Update-IR의 TCK 하강 엣지에 명령 래치
- **TDO:** TCK 하강 엣지에서만 바뀐다. `tdo_oe`는 Shift-IR/Shift-DR보다 반 주기 늦게 켜지고 꺼진다
- **TRST\*:** 모든 FF의 비동기 리셋에 직접 연결하고, 해제 동기화기는 두지 않는다(근거: [D-001](docs/decisions.md))
- **규모:** 플립플롭 49개 (posedge 42, negedge 7)

| IR 코드 | 명령 | 비고 |
|---|---|---|
| `0x01` | IDCODE (리셋 시 기본 명령) | `0xDEADBEEF` (학습용 값, [D-003](docs/decisions.md)) |
| `0x1F`, `0x00` | BYPASS | all-1 필수, all-0 권고 |
| 그 외 | BYPASS | 미할당 코드 규칙 |
| `0x02`, `0x04` | SAMPLE/PRELOAD, EXTEST | 2단계에서 추가 예정 |
| `0x10`, `0x11` | dtmcs, dmi | 3단계에서 추가 예정 |

## 검증

**RTL 테스트벤치** (`tb/tb_tap.sv`, `tb/jtag_drv.svh`)
- 시나리오 10개:
  - S1 리셋 후 IDCODE
  - S2 Capture-IR `01`
  - S3 BYPASS 1비트 지연
  - S4 미할당 IR 코드
  - S5 16개 상태 각각에서 TMS=1 다섯 번으로 TLR 복귀
  - S6 TRST* 비동기 리셋
  - S7 Pause/Exit2 경유 연속성
  - S8 `tdo_oe` 구간
  - S9 TDO가 하강 엣지에서만 변하는지
  - S10 3-TAP 체인 탐지
- 상시 모니터: 참조 FSM 모델과 `tdo_oe`를 비교하고, TDO가 하강 엣지에서만 변하는지 검사한다
- 결과: Verilator 5.020과 Icarus Verilog 12.0 모두 `ALL TESTS PASSED`, TAP arc 커버리지 32/32, `verilator --lint-only -Wall` 경고 0
- 변이 검사: RTL에 버그를 하나씩 넣은 8종이 모두 FAIL로 잡혔다

**OpenOCD 연동** (`sim/`, `openocd/`)
- Verilator 모델과 remote_bitbang 서버를 OpenOCD 0.12에 연결한다
- `tap/device found: 0xdeadbeef`를 확인했다
- IDCODE·BYPASS 스캔과, SVF로 작성한 TRST* 검사도 통과했다

**post-route GLS** (`gls/run_gls.sh`)
- Xcelium에서 SDF를 역주석해 같은 테스트벤치를 돌린다
- max(slow)와 min(fast) 코너 모두 `ALL TESTS PASSED`, 타이밍 위반 0
- 편차 1건: S6c의 TRST* 해제 시점([D-006](docs/decisions.md))

## 구현 결과

목표 TCK 50 MHz(20 ns) 기준이다. 전체 기록은 [docs/results.md](docs/results.md)에 있다.

| 항목 | Genus (합성) | Innovus (post-route) |
|---|---|---|
| 셀 면적 | 646.0 µm² | 574.6 µm² (다이 45.2 × 44.65 µm) |
| 셀 수 / FF 수 | 181 / 49 | 182 / 49 |
| setup WNS | +4.996 ns | +5.490 ns |
| hold WNS | — | +0.083 ns |
| 전력 (기본 활동도 추정) | 16.5 µW | 8.5 µW |
| 검사 | latch 0, unmapped 0 | DRC 0, connectivity 문제 없음 |

- 평가·시연용 데모 라이브러리를 썼으므로 수치는 툴 데모 수준이다.
- 사인오프 DRC/LVS 툴(Calibre, Pegasus)이 없어 LVS는 수행하지 못했다. DRC는 Innovus 내장 검사 결과다.

## 디렉터리

```
rtl/       jtag_tap.v, kh_jtag_top.v          Verilog-2001 RTL
tb/        tb_tap.sv, jtag_drv.svh            SystemVerilog 테스트벤치 (RTL/GLS 공용)
sim/       rbb_server.*, main_tap.cpp, Makefile, check_openocd_tap.sh
openocd/   sim_tap.cfg, check_trst.svf
syn/       syn.tcl, constraints.sdc           Genus 23.14 (Stylus)
pnr/       pnr.tcl, mmmc.tcl                  Innovus 23.14 (Stylus)
gls/       run_gls.sh                         Xcelium 23.09 post-route GLS
docs/      spec_notes.md, decisions.md, results.md
CLAUDE.md  프로젝트 규칙: 코딩 규칙, 스펙 상수, 단계별 완료 기준
```

## 실행 방법

### 시뮬레이션과 OpenOCD (WSL2 Ubuntu 24.04)

필요한 것: Verilator 5.x, Icarus Verilog 12, OpenOCD 0.12 (Ubuntu 24.04 apt 패키지로 설치 가능). 모두 프로젝트 루트에서 실행한다.

```bash
verilator --lint-only -Wall -Irtl rtl/jtag_tap.v
```

```bash
verilator --binary --timing -Wall -Itb -Irtl --top-module tb_tap tb/tb_tap.sv rtl/jtag_tap.v -o tb_tap && ./obj_dir/tb_tap
```

```bash
iverilog -g2012 -Wall -Wno-timescale -Itb -o sim/tb_tap.vvp tb/tb_tap.sv rtl/jtag_tap.v && vvp -n sim/tb_tap.vvp
```

OpenOCD 연동은 시뮬레이터 빌드·실행부터 OpenOCD 스캔과 판정까지 한 번에 돌린다.

```bash
bash sim/check_openocd_tap.sh
```

### 합성, P&R, GLS (Cadence 툴이 있는 서버)

라이브러리 위치는 환경변수로 지정한다(csh: `setenv GSCLIB045_ROOT <dir>/gsclib045_all_v4.7/gsclib045`). 아래 명령은 서버에 둔 프로젝트 사본의 루트에서 차례로 실행한다.

```bash
genus -batch -abort_on_error -no_gui -files syn/syn.tcl -log syn/rpt/genus
```

```bash
innovus -stylus -batch -abort_on_error -no_gui -files pnr/pnr.tcl -log pnr/rpt/innovus
```

```bash
bash gls/run_gls.sh
```

## 저장소에 없는 것

- **IEEE 1149.1-2013 원문:** 저작권 문서라 올리지 않았다. [docs/spec_notes.md](docs/spec_notes.md)에는 조항 번호와 요약만 있다.
- **라이브러리 파생물:** 넷리스트, SDF, DEF, 리포트, 툴 로그. 라이브러리 라이선스가 배포를 금지하기 때문이다([D-007](docs/decisions.md)). 위 스크립트로 다시 만들 수 있다.

## 문서

- [docs/spec_notes.md](docs/spec_notes.md): IEEE 1149.1-2013 조항 요약과 RTL 반영 위치
- [docs/decisions.md](docs/decisions.md): 설계 결정과 스펙 편차 (D-001 ~ D-007)
- [docs/results.md](docs/results.md): 실행 환경, 검증 결과, 합성·P&R·GLS 수치, 완료 기준 현황

## 참고 규격

- IEEE Std 1149.1-2013, Standard for Test Access Port and Boundary-Scan Architecture
- RISC-V External Debug Support 0.13.2 (3단계, v1.0 참조)
