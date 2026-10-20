# CLAUDE.md — kh-jtag: IEEE 1149.1 TAP → Boundary Scan → RISC-V JTAG-DTM/DM (ASIC 45nm)

## 0. 프로젝트 목표
- 1단계: IEEE 1149.1-2013 TAP 컨트롤러(16-state FSM, IR 5-bit, BYPASS, IDCODE)를 Verilog-2001로 구현하고
  SV 테스트벤치 + Verilator/OpenOCD(remote_bitbang)로 검증. Genus 합성 → Innovus P&R → GLS까지 완료.
- 2단계: Boundary-scan 셀/BSR + SAMPLE, PRELOAD, EXTEST (1149.1-2013 필수 명령 완비) + BSDL.
- 3단계: RISC-V Debug Spec(0.13.2 호환, v1.0 참조) JTAG-DTM(dtmcs/dmi) + 최소 Debug Module을
  RV32 코어에 연결, Verilator 시뮬에서 OpenOCD/GDB로 halt/resume/레지스터 접근 시연.
- 구현 환경: Cadence Genus + Innovus, 45nm 표준셀(GSCLIB045 v4.7, Cadence GPDK045 기반, `gsclib045_all_v4.7` 패키지 중 SVT `gsclib045` 사용). FPGA 보드 없음, 외부 JTAG 어댑터 없음.
  - 원격 Linux 서버 (CentOS 7.9, 로그인 셸 csh). 라이브러리 루트는 환경변수로 지정: `setenv GSCLIB045_ROOT <dir>/gsclib045_all_v4.7/gsclib045` (syn/pnr/gls 스크립트가 읽음)
    - Liberty: `timing/{slow,fast}_vdd1v0_basicCells.lib` (데모용 라이브러리 → PPA는 데모 수준임을 results.md에 명시)
    - LEF: `lef/gsclib045_tech.lef`, `lef/gsclib045_macro.lef` / QRC: `qrc/qx/gpdk045.tch` / GLS 셀 모델: `verilog/{slow,fast}_vdd1v0_basicCells.v` / GDS: `gds/`
  - 툴: Genus·Innovus DDI231 (23.14), Xcelium XCELIUMMAIN2309 (23.09, GLS). Calibre/Pegasus는 PATH에 없음 → 사인오프 DRC/LVS 불가, Innovus 내장 검사만.
  - IO 라이브러리 `giolib045_v3.3.tgz`(압축 상태)가 홈에 있음 → 2단계 패드 배치 시 검토.
- 모든 단계 산출물은 PPA 수치(면적 µm², 셀 수, post-route WNS/TNS, 목표 주파수, 전력)로 docs/results.md에 기록.

## 1. 디렉터리 구조
```
rtl/        Verilog-2001 RTL (*.v). 1 모듈 = 1 파일, 파일명 = 모듈명
  jtag_tap.v          # 1단계 TAP (FSM, IR, BYPASS, IDCODE, TDO@negedge)
  bsr_cell.v, bsr.v   # 2단계
  dtm_jtag.v          # 3단계 dtmcs/dmi DR + DMI req/resp (TCK 도메인)
  cdc_2phase.v        # 3단계 TCK<->clk 핸드셰이크
  dm_min.v            # 3단계 최소 DM (clk 도메인)
  kh_jtag_top.v       # 합성 top
tb/         SystemVerilog TB (*.sv), tb/jtag_drv.svh 공용 태스크. RTL/GLS 공용으로 작성
sim/        Verilator C++ (rbb_server.cpp, main_*.cpp), Makefile
openocd/    sim_tap.cfg, sim_riscv.cfg
syn/        Genus: syn.tcl, constraints.sdc, out/(netlist .vg, .sdc, .sdf), rpt/   # out/, rpt/는 저장소 미포함 (D-007)
pnr/        Innovus: pnr.tcl, mmmc.tcl, out/(netlist, .sdf, .def, .gds), rpt/  # out/, rpt/는 저장소 미포함 (D-007)
gls/        게이트 레벨 시뮬 스크립트 (post-syn / post-route, SDF 백어노테이션)
docs/       spec_notes.md(스펙 조항+요약), decisions.md(설계 결정/편차), results.md(수치), kh_jtag.bsd
```

## 2. 코딩 규칙 (반드시 준수)
- RTL은 Verilog-2001만: `reg/wire`, `always @*`, `always @(posedge clk or negedge rst_n)`.
  SystemVerilog 구문은 rtl/에 금지(tb/는 허용). `initial`, `#delay`, `$display` 금지.
- 정적 로직만 사용: TCK를 0에 멈춰도 상태가 무기한 유지되어야 함(1149.1-2013 4.2.1 a). 래치·동적 저장소 금지.
- 리셋: active-low `*_n`, 비동기 assert.
  - TCK 도메인: `trst_n`을 모든 TCK FF의 비동기 리셋에 직접 연결(해제 동기화기 없음) + Test-Logic-Reset 상태(동기)로 모든 TAP 상태 초기화.
    해제는 TCK 정지 중 또는 TMS=1 유지 중(1149.1-2013 4.6.1 e)으로 가정. TLR+TMS=1에서 모든 TCK FF의 D가 리셋값과 같도록 설계 (decisions.md D-001).
    POR이 없으므로 TRST* 포트는 필수(1149.1-2013 4.1.1 b).
  - clk 도메인: `rst_n` 비동기 assert / 동기 deassert (2-FF 리셋 동기화기).
- 클럭 도메인 분리:
  - 신호 접두사 TCK 도메인 `tck_`, 시스템 도메인 `sys_`. 도메인 간 직접 연결 금지, 반드시 `cdc_2phase` 경유.
  - `negedge tck`는 TDO 출력 FF, tdo_oe, IR/DR hold(Update) 레지스터에만 허용. 나머지 TCK 로직은 `posedge tck`.
  - RTL에서 클럭 게이팅/클럭 mux 직접 작성 금지(필요시 Genus ICG 삽입에 맡김).
- 네이밍: snake_case, 파라미터 UPPER_CASE, 레지스터 출력 `_q`, 다음값 `_d`.
- FSM: `localparam [3:0]` 상태 상수 + `always @*` next-state `case` + `default` 필수.
- 매직넘버는 localparam으로 두고 스펙 조항을 주석에 기록 (예: `// IEEE 1149.1-2013 7.1.1 d`).
- 합성 계층 유지: 모듈별 면적을 보고해야 하므로 top 아래 계층을 ungroup하지 않음.

## 3. 스펙 핵심 상수/규칙 (조항 명시, 변경 시 docs/decisions.md 갱신)
| 항목 | 값/규칙 | 출처 |
|---|---|---|
| TAP 핀 | TCK, TMS, TDI, TDO 필수 + TRST*(POR 없으면 필수), 전용 핀 | 1149.1-2013 4.1.1 |
| TDO 타이밍 | TDO 변화는 해당 상태 진입 후 TCK 하강 엣지. 출력 enable은 Shift 상태 첫 하강~이탈 후 첫 하강 | 1149.1-2013 6.1.2.1 d + NOTE 2 |
| IR 최소 길이 | 2 이상 (본 설계 5) | 1149.1-2013 7.1.1 a / RISC-V Debug §6.1 |
| IR 갱신 시점 | 명령 효과는 Update-IR, Test-Logic-Reset 상태에서만 변경 | 1149.1-2013 7.1.1 b |
| Capture-IR | 하위 2비트 `01` (LSB=1), 본 설계는 `5'b00001` | 1149.1-2013 7.1.1 d |
| 필수 명령 | BYPASS, SAMPLE, PRELOAD, EXTEST (2단계 완료 시 충족) | 1149.1-2013 8.2.1 b |
| 미할당 코드 | 모두 BYPASS와 동일 동작 | 1149.1-2013 8.1.1 d |
| 코드 공유 | 규칙을 만족하면 두 명령이 한 코드 공유 가능 (SAMPLE/PRELOAD) | 1149.1-2013 8.1.1 h |
| all-0 코드 | 시스템을 교란하는 명령(EXTEST 등)에 쓰지 말 것 권고 (TDI stuck-at-0 대비) | 1149.1-2013 8.1.1 f |
| BYPASS | 1-bit, all-1 코드 필수 | 1149.1-2013 8.4.1 a, b |
| IDCODE | ID 레지스터가 있으면 IDCODE 명령 제공, Capture-DR 진입 후 TCK 상승에서 로드 | 1149.1-2013 8.13.1 a, c |
| ID 제조사 코드 | `00001111111` 사용 금지. 예시값 32'hDEADBEEF는 [11:1]=0x777 → 허용. 12.2.1 c(소유사 JEP106 코드) 편차는 decisions.md D-003 | 1149.1-2013 12.2.1 b, c |
| IR 코드 표 | 0x00 BYPASS(권고), 0x01 IDCODE(리셋값), 0x10 dtmcs, 0x11 dmi, 0x12–0x17 reserved→BYPASS, 0x1f BYPASS | RISC-V Debug v1.0 §6.1 |
| 2단계 추가 코드 | SAMPLE/PRELOAD = 0x02(공유), EXTEST = 0x04 | 프로젝트 결정 (all-0 회피, RISC-V 코드와 비충돌) |
| dtmcs | idle[14:12]=1, abits[9:4]=7, version[3:0]=1 → 32'h0000_1071, dmireset bit16, dtmhardreset bit17 | Debug Spec dtmcs |
| dmi 포맷 | {addr[40:34], data[33:2], op[1:0]} (abits=7, 41-bit). 요청 0 nop/1 read/2 write, 응답 0 ok/2 fail/3 busy(sticky) | Debug Spec dmi |
| DM 주소 | data0 0x04, dmcontrol 0x10, dmstatus 0x11, abstractcs 0x16, command 0x17 | Debug Spec Ch.3 |
| dmstatus.version | 2 (0.13) 우선 | 0.13.2 호환 |
| regno | CSR 0x0000–0x0FFF, GPR 0x1000–0x101F | Debug Spec Access Register |

스펙 원문(1149.1-2013 PDF)은 저작권 문서이므로 docs/에 원문을 복사하지 말고 조항 번호 + 요약만 기록.

## 4. 타이밍 제약 (syn/constraints.sdc 기준값, PPA 스윕 시 변경)
```tcl
create_clock -name tck -period 20.0 [get_ports tck]      ;# 50 MHz 시작점
create_clock -name clk -period 2.0  [get_ports clk]      ;# 500 MHz 시작점 (3단계)
set_clock_groups -asynchronous -group {tck} -group {clk}
set_input_delay  -clock tck -clock_fall 4.0 [get_ports {tms tdi}] ;# 호스트가 TCK 하강에서 구동 → 하강 기준, 예산 = 반주기 - 4 ns (decisions.md D-002)
set_output_delay -clock tck 4.0 [get_ports {tdo tdo_oe}]  ;# negedge 발사 → 다음 상승 캡처 = 반주기 예산
set_false_path -from [get_ports {trst_n rst_n}]           ;# 비동기 리셋 (trst_n deassert는 TCK 정지 또는 TMS=1 중 가정, decisions.md D-001)
set_load 0.01 [all_outputs]                                ;# PDK 단위 확인 후 조정
```
- TDO 경로는 negedge FF → 출력이므로 반주기 경로임을 timing report에서 확인하고 docs에 기록.
- CDC는 `cdc_2phase`의 데이터 홀드 구조로 보장하며, async clock group으로 STA에서 제외됨. 동기화기 FF 셀은 리포트로 확인.

## 5. 단계별 작업 목록과 완료 기준
### 1단계 — TAP
- [x] rtl/jtag_tap.v, tb/jtag_drv.svh(`tick`, `reset_tms`, `shift_ir`, `shift_dr(n)`), tb/tb_tap.sv
- [x] TB 시나리오: 리셋 후 IDCODE / Capture-IR 01 / BYPASS 1-bit 지연·capture 0 / 미할당 IR→BYPASS /
      16개 상태 각각에서 TMS=1×5→TLR / TRST 비동기 / Pause·Exit2 경유 연속성 / tdo_oe 구간 /
      TDO가 TCK 하강에서만 변화 / 3-TAP 체인 IR 길이·디바이스 수 탐지
- [x] sim/rbb_server.cpp + openocd/sim_tap.cfg
- [x] syn/syn.tcl(Genus), pnr/pnr.tcl(Innovus), gls/ 스크립트 (현황: docs/results.md 1.8)
- 완료 기준:
  (a) RTL TB `ALL TESTS PASSED` + `TAP arc coverage: 32/32`, `verilator --lint-only -Wall` 경고 0
  (b) OpenOCD 로그에 `tap/device found: 0xdeadbeef`
  (c) Genus: latch 0, unmapped 0, WNS ≥ 0 / Innovus post-route: setup·hold WNS ≥ 0, DRC·LVS(가능 시) clean
  (d) post-route SDF GLS에서 동일 TB PASS
  (e) docs/results.md에 면적(µm²), 셀 수, FF 수, 목표 TCK 주파수, 전력 기록

### 2단계 — Boundary Scan
- [ ] bsr_cell.v(capture FF, update FF@TCK↓ in Update-DR, mode mux), bsr.v(N셀 체인)
- [ ] top의 기능 입출력 포트를 BSR로 래핑 (패드 라이브러리가 있으면 패드-코어 사이에 배치)
- [ ] SAMPLE/PRELOAD(0x02), EXTEST(0x04) 디코드, docs/kh_jtag.bsd
- 완료 기준: SAMPLE이 입력 핀 캡처, PRELOAD→EXTEST로 출력 핀이 프리로드 값 구동, 해제 시 기능 경로 복귀(RTL+GLS).
  BSDL의 INSTRUCTION_LENGTH/OPCODE/BOUNDARY_LENGTH가 RTL 파라미터와 일치. BSR 추가에 따른 면적·기능경로 지연 증가 기록.

### 3단계 — JTAG-DTM + 최소 DM
- [ ] dtm_jtag.v: Update-DR에서 req 발행, Capture-DR에서 resp 래치, 진행 중 Capture → op=3 sticky, dmireset/dtmhardreset
- [ ] cdc_2phase.v (req 41-bit, resp 34-bit; 핸드셰이크 동안 데이터 홀드)
- [ ] dm_min.v: dmcontrol(dmactive, haltreq, resumereq, ndmreset), dmstatus(all/any halted·running·resumeack,
      authenticated=1, version=2), abstractcs(busy, cmderr W1C, datacount=1, progbufsize=0),
      command(Access Register, aarsize=2만 지원, 그 외 cmderr=2), data0
- [ ] 코어 인터페이스: dbg_halt_req, dbg_resume_req, dbg_halted, dbg_running, 레지스터파일 debug 포트, dpc/dcsr
- 완료 기준: (a) TB: dtmcs==32'h1071, dmi write→read 왕복, busy 유발→dmireset 복구
  (b) Verilator+OpenOCD sim_riscv.cfg: examine, halt, reg pc, resume 성공 + GDB 접속
  (c) DTM+DM 합성/P&R, 코어 대비 디버그 로직 면적 비율(%) 기록

## 6. 검증·구현 명령
```bash
verilator --lint-only -Wall -Irtl rtl/jtag_tap.v
verilator --binary --timing -Wall -Itb -Irtl --top-module tb_tap tb/tb_tap.sv rtl/jtag_tap.v -o tb_tap && ./obj_dir/tb_tap
iverilog -g2012 -Wall -Wno-timescale -Itb -o sim/tb_tap.vvp tb/tb_tap.sv rtl/jtag_tap.v && vvp -n sim/tb_tap.vvp   # 교차 시뮬
make -C sim rbb_tap && ./sim/obj_dir/Vrbb_tap +port=9999   # 터미널 1
openocd -f openocd/sim_tap.cfg                              # 터미널 2
bash sim/check_openocd_tap.sh                               # 위 두 단계 자동 실행 + IDCODE/BYPASS/TRST(SVF) 판정
genus -batch -abort_on_error -no_gui -files syn/syn.tcl -log syn/rpt/genus   # 서버 ~/kh-jtag에서. -log는 접두어(genus.log/.cmd 생성)
innovus -stylus -batch -abort_on_error -no_gui -files pnr/pnr.tcl -log pnr/rpt/innovus   # 서버. 로그 "**ERROR" 0줄도 확인
bash gls/run_gls.sh                                         # 서버. post-route GLS max/min (Xcelium + $sdf_annotate)
```
- 모든 TB는 마지막 줄에 `ALL TESTS PASSED` 또는 `N FAILURES` 출력, 실패 시 non-zero exit.
  실패 시 시뮬레이터가 그 뒤에 자체 메시지를 덧붙이므로(Verilator `Aborting...` exit 134, iverilog `FATAL` exit 1) 판정은 exit code + 요약 줄 grep (docs/results.md §0).
- 명령은 WSL2 Ubuntu-24.04의 프로젝트 루트(`/mnt/c/Users/sions/Desktop/kh-jtag`)에서 실행.
- genus/innovus/gls 명령은 서버의 프로젝트 사본(`~/kh-jtag`)에서, `GSCLIB045_ROOT`를 설정한 뒤 실행.
- Genus/Innovus 명령은 설치된 버전(Stylus/legacy UI)에 맞춰 확인 후 작성. 추측한 명령으로 스크립트를 완성됐다고 보고하지 말 것.
- 리포트는 syn/rpt, pnr/rpt에 저장: area(계층별), timing(setup/hold, TDO 경로 포함), power, qor.
  라이브러리 파생물(넷리스트·SDF·DEF·리포트)은 라이선스상 공개 저장소에 올리지 않는다 (docs/decisions.md D-007).

## 7. 하지 말아야 할 것
- 스펙에 없는 동작을 추측해 구현하지 말 것. 불명확하면 docs/spec_notes.md에 "UNVERIFIED"로 남기고 질문.
- 실행 결과(로그·리포트) 없이 "완료/동작함/타이밍 만족"이라고 주장하지 말 것. 명령과 출력 발췌 포함.
- TB 기대값을 RTL 결과에 맞춰 수정하지 말 것 (기대값은 스펙에서 유도).
- 도메인 간 신호를 동기화기 없이 연결하지 말 것. SDC로 타이밍 위반을 가리려고 false path를 임의 추가하지 말 것.
- TDO를 posedge에서 갱신하거나, Shift→Exit1 전이 엣지의 마지막 시프트를 생략하지 말 것.
- 외부 코드(pulp/Hazard3/OpenCores)를 그대로 복사하지 말 것. 참고 시 출처·라이선스를 decisions.md에 기록.
- 한 단계 완료 기준 충족 전에 다음 단계로 넘어가지 말 것.
