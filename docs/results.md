# results.md — 실행 결과와 PPA 수치

모든 수치는 출처 로그/리포트 경로와 함께 기록한다.

---

## 0. 실행 환경 (2026-10-20 확인)

| 항목 | 값 | 확인 명령 |
|---|---|---|
| 호스트 | Windows 11 + WSL2 `Ubuntu-24.04` (Ubuntu 24.04.5 LTS), 커널 `6.18.33.1-microsoft-standard-WSL2` | `wsl -l -v`, `uname -r` |
| Verilator | 5.020 2024-01-01 rev (Debian 5.020-1) | `verilator --version` |
| Icarus Verilog | 12.0 (stable) | `iverilog -V` |
| OpenOCD | 0.12.0, `remote_bitbang` 드라이버 포함 | `openocd --version`, `openocd -c 'adapter list' -c shutdown` |
| g++ / make / Python | 13.3.0 / GNU Make 4.3 / 3.12.3 | `--version` |
| 프로젝트 경로 (WSL) | `/mnt/c/Users/sions/Desktop/kh-jtag` | — |
| 구현 서버 | 원격 Linux 서버, CentOS Linux 7.9.2009, 로그인 셸 `/bin/csh` | `/etc/redhat-release` |
| Genus / Innovus | Cadence DDI231 설치본 (설치 디렉터리명 기준 23.1, 정확한 버전은 첫 실행 로그로 확인) | csh `which` |
| GLS 시뮬레이터 | Cadence XCELIUMMAIN2309 설치본의 `xrun` | csh `which` |
| DRC/LVS 사인오프 | Calibre, Pegasus 모두 PATH에 없음 → Innovus 내장 검사(geometry/connectivity)만 가능 | csh `which` |
| 표준셀 라이브러리 | GSCLIB045 v4.7 (Cadence, GPDK045 generic 45nm 기반), `gsclib045_all` 패키지의 SVT `gsclib045` 사용 | `gsclib045/Release_Note.txt` |
| 라이브러리 경로 | `<dir>/gsclib045_all_v4.7/gsclib045/` 아래 `timing/{slow,fast}_vdd1v0_basicCells.lib`, `lef/gsclib045_tech.lef`, `lef/gsclib045_macro.lef`, `qrc/qx/gpdk045.tch`, `verilog/{slow,fast}_vdd1v0_basicCells.v` | `ls`, `find` |
| 라이브러리 주의 | 평가·시연용 데모 라이브러리다. PPA 수치는 툴 데모 수준이다 | 라이브러리 문서 |

시뮬레이터 동작 확인 (scratchpad 스모크 TB로 확인, 프로젝트 코드 아님):

| | 성공 | 실패 (`$fatal(1, ...)`) |
|---|---|---|
| Verilator `--binary --timing -Wall` | exit 0 | exit 134 (abort). TB의 `N FAILURES` 뒤에 Verilator가 `%Fatal`, `Aborting...` 줄을 덧붙임 |
| iverilog `-g2012` + `vvp -n` | exit 0 | exit 1. TB의 `N FAILURES` 뒤에 `FATAL:` 줄이 붙음 |

정리:
- Verilator는 `-Wall`로 빌드하면 TB 코드의 경고도 빌드를 멈춘다. 그래서 TB도 lint 경고가 없어야 한다.
- 실패할 때는 시뮬레이터가 TB 요약 줄 뒤에 자체 메시지를 덧붙인다. TB의 마지막 출력은 요약 줄이고, 판정은 **exit code**와 **요약 줄(`ALL TESTS PASSED` 또는 `N FAILURES`) grep**을 함께 본다.

---

## 1. 1단계 — TAP

### 1.1 TB RED 확인 (2026-10-20, RTL 구현 전)

`tb/tb_tap.sv` + `tb/jtag_drv.svh`를 출력이 0으로 고정된 스텁(scratchpad, 커밋 안 함, 포트만 계획대로)과 함께 빌드했다.
- 빌드: Verilator `--binary --timing -Wall` 경고 0, iverilog `-g2012 -Wall -Wno-timescale` 경고 0.
- 실행: 두 시뮬레이터 결과가 같았다.
  - `3392 FAILURES` (Verilator exit 134, iverilog exit 1)
  - S1~S10 모두 FAIL. 시나리오별 실패 수도 양쪽이 동일했다.
  - `TAP arc coverage: 32/32`
  - TB 내부 오류(참조 모델 기준 경로 이탈) 0건
- 해석: 실패 원인은 TAP 동작이 없다는 것뿐이다. TDO 엣지 검사기는 출력이 바뀌지 않는 스텁에서는 동작하지 않으므로, RTL 구현 뒤 변이 검사(TDO posedge 갱신 등)로 검출력을 확인한다.

### 1.2 RTL GREEN (2026-10-20, `rtl/jtag_tap.v`)

명령은 CLAUDE.md §6, 실행 위치는 WSL 프로젝트 루트다.

| 항목 | 명령 | 결과 | 로그 |
|---|---|---|---|
| lint | `verilator --lint-only -Wall -Irtl rtl/jtag_tap.v` | exit 0, 출력 0바이트 | `sim/logs/lint_jtag_tap.log` |
| RTL TB (Verilator 5.020) | `verilator --binary --timing -Wall -Itb -Irtl --top-module tb_tap tb/tb_tap.sv rtl/jtag_tap.v -o tb_tap && ./obj_dir/tb_tap` | 빌드 경고 0. S1~S10 PASS, `TAP arc coverage: 32/32`, `ALL TESTS PASSED`, exit 0 | `sim/logs/tb_tap_verilator.log` |
| RTL TB (iverilog 12.0) | `iverilog -g2012 -Wall -Wno-timescale -Itb -o sim/tb_tap.vvp tb/tb_tap.sv rtl/jtag_tap.v && vvp -n sim/tb_tap.vvp` | 빌드 경고 0. 결과는 Verilator와 동일, exit 0 | `sim/logs/tb_tap_iverilog.log` |

- 상시 모니터: tdo_oe 불일치 0, TDO 엣지 위반 0.
- S10 체인 탐지 결과: IR 합계 15비트, 디바이스 3개.
- 시뮬 시간: 270.1 µs (TCK 10 MHz).

### 1.3 TB 변이 검사 (2026-10-20)

`rtl/jtag_tap.v`를 복사해 버그를 하나씩 넣은 변이본(scratchpad, 커밋 안 함)을 바꾸지 않은 TB로 돌렸다(iverilog). 모든 변이본이 FAIL하고 exit 1로 끝났다.

| 변이 | 위반 조항 | 결과 | FAIL 시나리오 |
|---|---|---|---|
| m1 TDO/tdo_oe를 TCK 상승에서 갱신 | 4.5.1 a, 6.1.2.1 d | 1563 FAILURES (엣지 위반 1152) | S1~S10 |
| m2 Capture-IR이 `00000` 로드 | 7.1.1 d | 61 FAILURES | S1~S10 |
| m3 TMS로 TLR 진입 시 IR을 IDCODE로 복귀 안 함 | 7.2.1 e | 17 FAILURES | S1, S5, S10 |
| m4 DR(ID+bypass)이 Shift→Exit1 엣지 시프트 누락 | Fig. 6-1, 4.4.1 c | 2 FAILURES | S7 |
| m4b bypass만 Shift→Exit1 시프트 누락 | 10.1.1, 4.4.1 c | 1 FAILURE | S7 |
| m4c IR만 Shift→Exit1 시프트 누락 | 7.1.1 c | 2 FAILURES | S4, S7 |
| m5 tdo_oe를 상태에서 바로 디코드(반 주기 지연 없음) | 6.1.2.1 NOTE 2 | 560 FAILURES | S1~S10 |
| m6 TRST*가 IR을 BYPASS로 리셋 | 7.2.1 f | 4 FAILURES | S1, S6, S7 |

- **TB 보강.** 처음에는 m4b가 `ALL TESTS PASSED`였다. BYPASS 경로에서 Shift→Exit1 엣지의 마지막 시프트가 빠져도 잡는 시나리오가 없었기 때문이다.
- **추가한 검사.** S7에 "BYPASS 4 + 4비트 Pause-DR 분할 스캔"을 넣었다. 기대값은 스펙에서 유도했다. Pause/Exit2를 거쳐도 Capture-DR을 지나지 않으므로, 결과는 연속 8비트 BYPASS 스캔 `{din[6:0], 0}`과 같아야 한다.
- **보강 후 결과.** m4b가 FAIL로 바뀌었고, 실제 RTL은 두 시뮬레이터에서 계속 PASS다.
- **남은 약점.** m4·m4b·m4c는 각각 1~2개 검사에서만 걸린다. 이 동작은 3단계에서 DTM의 Update-DR 값으로도 다시 검증한다.

### 1.4 OpenOCD 연동 — 완료 기준 (b) (2026-10-20)

**구성.** `sim/rbb_server.{h,cpp}`, `sim/main_tap.cpp`, `sim/Makefile`, `openocd/sim_tap.cfg`, `openocd/check_trst.svf`
- remote_bitbang 프로토콜은 OpenOCD 0.12.0의 `doc/manual/jtag/drivers/remote_bitbang.txt`와 `remote_bitbang.c`로 확인했다.
- reset 문자 극성(trst=1이 assert)은 `sysfsgpio.c`로 확인했다.

**명령.** `bash sim/check_openocd_tap.sh` (빌드 → `Vrbb_tap +port=9999` → OpenOCD 0.12.0)

| 항목 | 결과 |
|---|---|
| 빌드 (`make -C sim rbb_tap`, Verilator `-Wall`) | 경고 0 (`sim/logs/build_rbb_tap.log`) |
| 체인 탐지 | `Info : JTAG tap: kh.tap tap/device found: 0xdeadbeef (mfg: 0x777 (<unknown>), part: 0xeadb, ver: 0xd)` |
| `irscan 0x01` → `drscan 32 0` | `deadbeef` |
| `irscan 0x1f` / `0x00` → `drscan 8 0x4d` | `9a` / `9a` (기대값 `{in[6:0], 0}`, 10.1.1 b) |
| `svf openocd/check_trst.svf` (BYPASS 선택 → TRST* 펄스 → DR 32비트) | `svf file programmed successfully for 11 commands with 0 errors` |
| OpenOCD exit / 경고 | exit 0. 경고는 `gdb services need one or more targets defined` 1건뿐(1단계에는 CPU target이 없어 예상된 경고) |
| rbb 서버 통계 | writes 1794, reads 772, resets 3, unknown 0 |

**TRST 검사를 SVF로 한 이유.** OpenOCD 0.12에서 TRST 펄스 직후 IR 스캔 없이 `drscan`을 하면 OpenOCD 내부 단언(`driver.c:166`)이 걸려 abort한다. OpenOCD가 TRST 뒤 TAP을 bypass 상태로 모델링하기 때문이다. SVF 플레이어는 이 bookkeeping 없이 스캔한다.

**음성 확인.** 변이 m6(TRST*가 IR을 BYPASS로 리셋)로 같은 SVF를 돌리면 `tdo check error at line 16, READ = 0x0000000, WANT = 0xdeadbeef`가 나오고 OpenOCD는 exit 1이다. 이때도 `tap/device found: 0xdeadbeef`는 출력된다. OpenOCD init이 TMS로 TLR에 진입하기 때문이다. 그래서 TRST 경로는 SVF 검사가 있어야 잡힌다.

(합성·P&R·GLS·PPA 수치는 서버 실행 후 기록)
