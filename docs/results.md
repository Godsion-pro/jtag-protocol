# results.md — 실행 결과와 PPA 수치

모든 수치는 출처 로그/리포트 경로와 함께 기록한다.

`syn/rpt`, `syn/out`, `pnr/rpt`, `pnr/out`과 시뮬·툴 로그는 저장소에 포함하지 않는다. 라이브러리 라이선스가 배포를 금지하기 때문이다(decisions.md D-007). 아래 "근거" 열의 파일은 같은 스크립트로 서버에서 다시 만들 수 있다.

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
| Genus / Innovus | Cadence DDI231 설치본 (Genus 23.14-s090_1, Innovus 23.14-s088_1, 실행 로그로 확인) | csh `which` |
| GLS 시뮬레이터 | Cadence XCELIUMMAIN2309 설치본의 `xrun` (23.09-s013) | csh `which` |
| DRC/LVS 사인오프 | Calibre, Pegasus 모두 PATH에 없음 → Innovus 내장 검사(geometry/connectivity)만 가능 | csh `which` |
| 표준셀 라이브러리 | GSCLIB045 v4.7 (Cadence, GPDK045 generic 45nm 기반), `gsclib045_all` 패키지의 SVT `gsclib045` 사용 | `gsclib045/Release_Note.txt` |
| 라이브러리 경로 | `$GSCLIB045_ROOT` (= `<dir>/gsclib045_all_v4.7/gsclib045/`) 아래 `timing/{slow,fast}_vdd1v0_basicCells.lib`, `lef/gsclib045_tech.lef`, `lef/gsclib045_macro.lef`, `qrc/qx/gpdk045.tch`, `verilog/{slow,fast}_vdd1v0_basicCells.v` | `ls`, `find` |
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

### 1.5 Genus 합성 — 완료 기준 (c) Genus 부분 (2026-10-20)

**실행 조건**

| 항목 | 값 |
|---|---|
| 서버 / 툴 | 원격 서버, Genus 23.14-s090_1 (Stylus UI) |
| 명령 | 서버 `~/kh-jtag`에서 `genus -batch -abort_on_error -no_gui -files syn/syn.tcl -log syn/rpt/genus` → exit 0, 로그 Error 0줄 |
| 입력 | top `rtl/kh_jtag_top.v`(`jtag_tap` 1개 래핑, 계층 유지 `auto_ungroup none`), `syn/constraints.sdc`(1단계에는 clk·rst_n 포트가 없어 CLAUDE.md §4 중 tck 관련 줄만 사용) |
| 라이브러리 | `slow_vdd1v0_basicCells.lib` (PVT_0P9V_125C) + `gsclib045_tech.lef`, `gsclib045_macro.lef` |
| 판정 | `syn/rpt/summary.rpt`에 `CRITERION (c) GENUS: PASS`. 기준 미달이면 스크립트가 error로 종료한다 |

**결과** (TCK 20 ns = 50 MHz)

| 항목 | 값 | 근거 |
|---|---|---|
| latch | **0** (`hdl_error_on_latch true`, inst `.is_latch` 집계) | `summary.rpt` |
| unmapped | **0**. lib_cell 없는 inst를 셌다. 이 방법이 유효한지는 syn_generic 직후 294/294개가 잡힌 것으로 확인했다 | `summary.rpt` |
| setup WNS / TNS | **+4996 ps** / 0 | `qor.rpt`, `timing.rpt` |
| 최악 경로 | `tms`(TCK **하강** 10 ns + input delay 4 ns) → `tck_state_q_reg[0]/D`(TCK 상승 20 ns), data path 826 ps. D-002 `-clock_fall`이 적용됐다 | `timing.rpt` Path 1 |
| TDO 경로 | `tck_tdo_q_reg/CKN`(TCK 하강 10 ns) → `tdo`, required 16 ns(20 − 4), slack **+5655 ps**. **반주기 경로**를 확인했다 | `timing_tdo.rpt` |
| 셀 수 | 181 (순차 49, 인버터 9, 논리 123) | `gates.rpt`, `qor.rpt` |
| FF 수 / 종류 | **49** (계획값과 같음). DFFSHQX1 24, DFFRHQX1 13, DFFNSRX1 5, DFFNSRX2 2, DFFRX2 4, DFFSX1 1. negedge 7비트(IR 출력 5 + TDO + oe)는 DFFNSR | 넷리스트 |
| 면적 | 셀 **646.038 µm²** (순차 343.710, 53.2%), 넷 포함 861.242 µm². `jtag_tap` 계층 646.038 / 854.666 | `area.rpt` |
| 면적 단위 확인 | lib area 값이 LEF 셀 크기(µm)의 곱과 일치해 단위가 µm²임을 확인 | lib / LEF 대조 |
| 전력 | **16.54 µW** (leakage 0.014 µW, internal 8.87 µW, switching 7.66 µW; register 55.6%, logic 42.0%, clock 2.4%). 벡터 없이 기본 토글률로 추정한 값이다 | `power.rpt` |
| check_design | 0이 아닌 항목은 둘이다. `Constant Leaf Pin(s) 7`은 안 쓰는 리셋 핀을 1로 묶은 것(SN=1 6개, RN=1 1개)이다. `Physical (LEF) cells with no libcell 96`은 basicCells.lib 밖의 LEF 셀이다. `Libcells with no LEF cell 0` | `check_design.rpt` |

**참고**
- **QoR의 `Min Fanout 0 (trst_n)`.** 연결 문제가 아니다. 넷리스트에서 FF 49개 모두 trst_n을 받는다(`.RN(trst_n)` 23, `.SN(trst_n)` 26). false path로 지정된 비동기 넷이라 fanout 집계에서 빠진 것으로 보인다.
- **로그 경고 6종.**
  - 라이브러리 관련: `LBR-9` 20건, `PHYS-279` 20건
  - 메시지 출력 상한: `MESG-11` 2건
  - `CHKTMG-19`: 요청한 경로 수보다 위반 경로가 적다는 안내
  - `CDFG-472`: 4비트 상태를 16개 모두 case로 다뤄 `default`에 도달할 수 없다는 안내. CLAUDE.md §2가 `default`를 요구하므로 유지한다
  - `SYNTH-33`: 다음 릴리스부터 `syn_opt -logical`을 권장한다는 안내. 이 옵션은 도움말에 "Innovus based ... limited access"로 나와 있어 23.14에서는 `syn_opt`를 유지했다
- **hold.** Genus `report_timing`에는 early(hold) 옵션이 없다. hold는 Innovus post-route에서 확인한다.
- **라이브러리 한계.** 데모용 라이브러리이므로 위 수치는 툴 데모 수준이다(§0).

### 1.6 Innovus P&R — 완료 기준 (c) Innovus 부분 (2026-10-20)

**실행 조건**

| 항목 | 값 |
|---|---|
| 툴 / 명령 | Innovus 23.14-s088_1, Stylus UI. 서버 `~/kh-jtag`에서 `innovus -stylus -batch -abort_on_error -no_gui -files pnr/pnr.tcl -log pnr/rpt/innovus` → exit 0, 로그 `**ERROR` 0줄, 실행 4분 8초 |
| MMMC (`pnr/mmmc.tcl`) | setup `view_setup` = slow_vdd1v0 (0.9 V / 125 °C) + QRC `gpdk045.tch` 125 °C. hold `view_hold` = fast_vdd1v0 (1.1 V / 0 °C) + QRC 0 °C. SDC는 `syn/constraints.sdc`. 분석 모드 OCV |
| 플로우 | 아래 순서 |

플로우 순서:
1. floorplan: 행 밀도 0.6, 여백 6 µm
2. core ring Metal9/Metal8 (폭 1 µm, 간격 0.5 µm) + `route_special -connect core_pin`
3. 핀 배치: 입력은 왼쪽, 출력은 오른쪽 (Metal3)
4. `place_opt_design` → `add_tieoffs` → `clock_opt_design` → `opt_design -post_cts -hold` → `route_design` → `opt_design -post_route -setup -hold` → `add_fillers`

**판정** (완료 기준 (c) Innovus 부분)

| 항목 | 결과 | 근거 |
|---|---|---|
| post-route setup | WNS **+5.490 ns**, TNS 0, 위반 0 / 51 경로 (reg2reg +8.544 ns) | `time_setup/post_route.summary.gz` |
| post-route hold | WNS **+0.083 ns**, TNS 0, 위반 0 / 51 경로 (reg2reg가 최악, I/O 경로 +14.024 ns) | `time_hold/post_route_hold.summary.gz` |
| DRV | max_cap / max_tran / max_fanout / max_length 모두 0 | setup summary |
| DRC | `No DRC violations were found` (`check_drc`, Innovus 내장 LEF 규칙) | `check_drc.rpt` |
| connectivity | `Found no problems or warnings.` (`check_connectivity -type all`) | `check_connectivity.rpt` |
| 배치 | `check_place`: Placed 320 (필러 포함), Unplaced 0 | `innovus.log` |
| LVS | 수행 불가. Calibre / Pegasus가 없다(§0) | — |

**경로 상세**

| 경로 | slack | 비고 |
|---|---|---|
| setup 최악 | +5.490 ns | `tms` → `tck_state_q_reg[0]/D`. 입력 지연 4 ns가 TCK 하강 기준이다(D-002) |
| TDO 출력 | +5.692 ns | `tdo`, required 16.0 ns = 20 − output delay 4. 반주기 경로 |
| hold 최악 | +0.083 ns | `tck_bypass_q_reg/D` (reg2reg). 다음은 `tck_ir_q_reg[0]` (negedge) +0.087 ns |

**물리 결과**

| 항목 | 값 | 근거 |
|---|---|---|
| 다이 | 45.2 × 44.65 µm (DEF 단위 2000/µm), 행 19개 | `kh_jtag_top.def` |
| 표준셀 밀도 | 53.3 % (필러 포함 100 %) | timing summary |
| 셀 수 / 면적 | 182개 (Genus 181 + TIEHI 1), **574.560 µm²** | `area.rpt` |
| 면적 감소 | Genus 646.0 µm²에서 줄었다. 배치 후 최적화가 셀 크기를 줄인 것으로 보인다(setup 여유 5 ns 이상) | — |
| 클럭 트리 | sink 49, 클럭 버퍼·인버터 0개, skew 0.001 ns (목표 0.097 ns) | `innovus.log` CCOpt 요약 |
| 전력 | **8.53 µW** (internal 7.76, switching 0.76, leakage 0.011 µW; 순차 84.8 %). Innovus 기본 활동도 기준이라 Genus 16.54 µW와 가정이 다르다 | `power/power.rpt` |
| 출력물 | `pnr/out/kh_jtag_top.pnr.vg`, `.def`, `.pnr.sdf`. `kh_jtag_top.db`(5.8 MB)는 서버에만 둔다 | — |
| SDF 설정 | max = view_setup, min = view_hold. SDF 2.1 형식에 `-map_recrem split -map_removal`: RECOVERY 56 + HOLD(removal) 56 + SETUPHOLD 105 + WIDTH 154. 기본값인 RECREM 병합으로는 셀 모델의 `$recovery`/`$hold` 224개가 전혀 주석되지 않아서 바꿨다(1.7). 이 변경 후 P&R을 다시 돌렸고 timing·DRC·connectivity 결과는 같았다 | — |

**한계와 메모**
- **tck 포트 모델링.** SDC에 `tck` 포트의 구동 셀이나 입력 전이가 없어서 포트가 이상적 드라이버로 취급된다. 그래서 CTS가 버퍼를 넣지 않았다. 실제 칩에서는 입력 패드가 49개 sink를 구동하므로, 패드나 드라이버 모델링은 2단계 패드 검토 때 반영한다.
- **hold 여유.** hold slack +83 ps는 기준(≥ 0)은 만족하지만 작다. fast 코너에서 클럭 skew가 거의 0이고 FF 간 직결 경로이기 때문이다.
- **GDS 미생성.** Innovus용 stream map 파일이 없고 사인오프 DRC/LVS 툴도 없기 때문이다.
- **스크립트 수정 이력.** 처음 두 번의 실행에서 고친 것:
  - PG 넷 미정의(IMPDB-1216) → `init_power_nets VDD`, `init_ground_nets VSS` 추가
  - `place_opt_design` 이후 `ccopt_design` 거부(IMPCCOPT-2440) → `clock_opt_design`으로 변경
  - post-route SI 최적화는 OCV 모드 필요(IMPOPT-6080) → `timing_analysis_type ocv`
- **오류 검출 방법.** `-abort_on_error`는 Tcl 오류에서만 멈추므로, 로그의 `**ERROR` 개수도 함께 확인한다.

### 1.7 post-route GLS — 완료 기준 (d) (2026-10-20)

**실행 조건**

| 항목 | 값 |
|---|---|
| 툴 / 명령 | Xcelium `xrun` 23.09-s013. 서버 `~/kh-jtag`에서 `bash gls/run_gls.sh` (max, min 차례로) |
| DUT | `pnr/out/kh_jtag_top.pnr.vg`. TB에서 `GLS` 정의 시 `kh_jtag_top`을 4개(단일 + 3-TAP 체인) 인스턴스한다 |
| 셀 모델 | max: `verilog/slow_vdd1v0_basicCells.v`, min: `verilog/fast_vdd1v0_basicCells.v` |
| SDF | `pnr/out/kh_jtag_top.pnr.sdf`를 인스턴스마다 `$sdf_annotate`. max는 `MAXIMUM`, min은 `MINIMUM`(`GLS_MIN` 정의) |
| TB | RTL과 같은 `tb/tb_tap.sv`. GLS에서 다른 점은 둘이다. `TDO_DLY_MAX` = 5 ns(TDO가 TCK 하강 후 5 ns 안에 바뀌어야 함). S6c의 TRST* 해제 시점(D-006) |

**결과**

| 항목 | max (slow 0.9 V / 125 °C) | min (fast 1.1 V / 0 °C) |
|---|---|---|
| 결과 | **`ALL TESTS PASSED`**, xrun exit 0 | **`ALL TESTS PASSED`**, xrun exit 0 |
| 시나리오 | S1~S10 모두 PASS | S1~S10 모두 PASS |
| 모니터 | tdo_oe 불일치 0, TDO 엣지 위반 0 | 같음 |
| arc 커버리지 | 32/32 | 32/32 |
| SDF 주석률 | path delay 2104, `$setuphold` 420, `$width` 616, `$recovery` 224, `$hold` 224 모두 100 % | 같음 |
| 타이밍 위반 / `*E`·`*F` | 0 / 0 | 0 / 0 |
| 시뮬 종료 | 270,138 ns, `$finish` | 같음 |

로그: `gls/logs/gls_max.log`, `gls/logs/gls_min.log`

**진행 기록**
1. **1차.** RECREM 병합 SDF를 썼다. 결과는 PASS였지만 셀 모델의 `$recovery`/`$hold`(removal) 224개가 0 % 주석이었다. TRST 해제 타이밍 검사가 사실상 꺼진 상태였으므로 PASS로 인정하지 않았다.
2. **2차.** `write_sdf -version 2.1 -map_recrem split -map_removal`로 SDF를 바꾸고 P&R을 다시 돌렸다. 주석률은 100 %가 됐다. 대신 S6c의 동시 해제에서 recovery/removal 위반이 났고, notifier가 X를 만들어 S6c가 80건 FAIL했다(다른 시나리오는 PASS).
3. **3차.** D-006에 따라 GLS의 S6c 해제 시점만 저위상 중간으로 옮겼다. 두 코너 모두 PASS, 위반 0건.

**남은 경고**
- `SDFNL1` 96건(인스턴스당 24건): 음수 limit을 단일 limit 검사(`$hold`, `$recovery`)에 넣을 수 없어 0으로 잘랐다는 내용이다. 0이 더 엄격하므로 보수적인 처리다.
- `DLCPTH` 180건: Xcelium 설치 디렉터리의 cds.lib 경로 경고(환경)다.

### 1.8 1단계 완료 기준 현황 (2026-10-20)

| 기준 | 상태 | 근거 |
|---|---|---|
| (a) RTL TB `ALL TESTS PASSED` + arc 32/32, lint 경고 0 | **충족** | 1.2, 1.3 (Verilator·iverilog, 변이 8종 검출) |
| (b) OpenOCD `tap/device found: 0xdeadbeef` | **충족** | 1.4 |
| (c) Genus latch 0 / unmapped 0 / WNS ≥ 0 | **충족** | 1.5 (WNS +4996 ps) |
| (c) Innovus post-route setup·hold WNS ≥ 0, DRC clean | **충족** | 1.6 (+5.490 / +0.083 ns, DRC 0, connectivity 문제 없음) |
| (c) LVS | **수행 불가** | Calibre/Pegasus 없음 (§0) |
| (d) post-route SDF GLS 동일 TB PASS | **충족 (편차 1건)** | 1.7. S6c 해제 시점 편차는 D-006 |
| (e) 면적, 셀 수, FF 수, 목표 TCK, 전력 | **기록함** | 아래 PPA 요약 |

**PPA 요약**

| 항목 | Genus (합성) | Innovus (post-route) |
|---|---|---|
| 목표 TCK | 50 MHz (20 ns) | 50 MHz (20 ns) |
| 셀 면적 | 646.0 µm² | 574.6 µm² (다이 45.2 × 44.65 µm) |
| 셀 수 / FF 수 | 181 / 49 | 182 (TIEHI 포함) / 49 |
| setup WNS | +4.996 ns | +5.490 ns |
| hold WNS | — | +0.083 ns |
| 전력 | 16.5 µW | 8.5 µW |

전력은 두 툴 모두 벡터 없이 기본 활동도로 추정한 값이다. 라이브러리가 데모용 특성화이므로 모든 수치는 데모 수준이다(§0).
