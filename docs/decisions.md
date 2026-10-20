# decisions.md — 설계 결정 / 스펙 편차

형식: 문제 → 스펙 근거 → 검토한 선택지·사례 → 결정 → 남는 위험/검증 방법. 상태는 `확정` 또는 `잠정`.

---

## D-001 TCK 도메인 `trst_n` 해제: 동기화기 없이 직접 비동기 리셋 (확정, 2026-10-20)

**문제.** CLAUDE.md §2는 "비동기 assert / 동기 deassert"를 일반 리셋 규칙으로 두었다. 반면 TCK 도메인 설명과 §4 SDC(`set_false_path -from trst_n`, "deassert는 TCK 정지 중 가정")는 해제 동기화기가 없는 구조를 전제한다. 두 규칙이 서로 맞지 않았다.

**스펙 근거.**
- 6.1.3.1 c: TRST*에 의한 초기화는 클럭과 무관하게 비동기로 일어나야 한다 (assert 쪽 요구).
- 4.6.1 a: TRST*=0이면 TAP는 비동기로 TLR이 된다.
- 4.6.1 e (Rec): TRST*가 0→1로 바뀌는 동안 TMS를 1로 유지하는 것이 좋다. 해제가 비동기로 일어날 수 있다는 전제의 권고다.
- 6.1.1.1 b: 모든 상태 전이는 TCK 상승 시점의 TMS로 결정된다. TCK 2-FF 해제 동기화기를 넣으면, 해제 직후 상승 엣지 2개 동안 TMS=0이어도 TLR에 머물러 이 규칙과 어긋난다.

**업계 사례 조사.** 코드는 복사하지 않고 리셋 연결 방식만 확인했다.

| 구현 | TRST 처리 | 출처 / 라이선스 |
|---|---|---|
| pulp-platform/riscv-dbg `src/dmi_jtag_tap.sv` | `trst_ni`를 TCK posedge FF(상태, IR, IDCODE, bypass)와 TDO FF의 비동기 리셋에 직접 연결. 동기화기 없음 | github.com/pulp-platform/riscv-dbg, SHL-0.51 |
| lowRISC/opentitan `hw/ip/rv_dm/rtl/rv_dm.sv` | 위 TAP을 사용. `trst_n`은 다른 리셋과 결합하거나 동기화하지 않고 연결. scan mode에서만 scan reset과 mux, 디버그 비활성 시 0으로 게이팅 | github.com/lowRISC/opentitan, Apache-2.0 |
| Wren6991/Hazard3 `hdl/debug/dtm/hazard3_jtag_dtm.v`, `hazard3_jtag_dtm_core.v` | `trst_n`을 TAP 상태와 TCK 도메인 FF의 비동기 리셋에 직접 연결. 동기화기 없음 | github.com/Wren6991/Hazard3, Apache-2.0 |
| chipsalliance/rocket-chip `src/main/scala/jtag/JtagTap.scala` | TAP에 TRSTn 핀을 두지 않음(`hasTRSTn=false`). 코드 주석상, TRSTn을 쓸 경우 TAP 밖에서 POR과 결합하고 TCK에 동기화한 뒤 async `jtag_reset`으로 넣는 방식 | github.com/chipsalliance/rocket-chip, `LICENSE.jtag` |
| TI TMS320C6748 데이터시트 (JTAG 절) | 이 디바이스의 TRST는 TCK로 클럭되는 동기식이라고 명시. 제품별 구현 사례 | ti.com 데이터시트 ZHCSGV3G |

정리하면 해제 동기화 방식은 두 가지가 쓰인다.
- **직접 비동기:** 전용 TRST 핀을 그대로 쓰는 구조. pulp, OpenTitan, Hazard3가 이 방식이다.
- **2-FF 해제 동기화:** TRST를 POR 등 다른 리셋과 합치는 구조. rocket-chip이 이 방식이다.

본 설계는 전용 TRST 핀만 있고 POR이 없다. 또 6.1.3.1 b에 따라 시스템 리셋과 합치지 않으므로 직접 비동기 구조에 해당한다.

**결정.**
- `trst_n`을 TCK 도메인의 모든 FF(posedge와 negedge 모두)의 비동기 리셋에 직접 연결한다. 해제 동기화기는 두지 않는다.
- **설계 규칙:** TLR 상태에서 TMS=1이면, 모든 TCK 도메인 FF의 다음값(D)이 자기 리셋값과 같아야 한다. 그러면 해제가 TCK 엣지와 겹쳐 recovery/removal 위반이 나도 결과 상태가 같다. 3단계 `dtm_jtag.v`의 TCK FF에도 같은 규칙을 적용한다.
- **사용 조건:** 호스트는 TCK가 멈춘 동안 또는 TMS=1을 유지한 동안에만 TRST*를 해제한다. TB와 `rbb_server.cpp`는 이 조건을 지킨다. OpenOCD remote_bitbang은 리셋 명령을 클럭 비트와 별도 문자로 보내므로 TCK 엣지 없이 해제된다. 이 동작은 `rbb_server.cpp` 구현 때 확인한다.
- SDC의 `set_false_path -from [get_ports trst_n]`는 위 조건을 근거로 유지한다.

**남는 위험 / 검증.**
- 호스트가 TCK를 돌리면서 TMS=0으로 해제하면, 해제 후 첫 상승 엣지가 반영될지 불확정이다(TLR에 남거나 RTI로 감). 스펙 권고(4.6.1 e)를 벗어난 사용이므로 문서와 BSDL 주석에 조건을 적는다.
- TB 시나리오 6에서 TCK 정지 중 해제와 TMS=1 유지 중 해제를 모두 검증한다.
- 합성·P&R 리포트에서 `trst_n` 경로가 timing 검사에서 빠졌는지 확인하고 results.md에 기록한다.

---

## D-002 `tms`/`tdi` 입력 지연을 TCK 하강 엣지 기준으로 변경 (확정, 2026-10-20)

**문제.** CLAUDE.md §4는 주석에 "호스트가 TCK 하강에서 구동"이라고 쓰면서, 명령은 `set_input_delay -clock tck 4.0`(상승 엣지 기준)으로 두었다. 상승 기준이면 STA가 TMS/TDI 내부 예산을 한 주기 − 4 ns(20 ns 주기에서 16 ns)로 계산한다. 하강 구동이 실제라면 예산은 반 주기 − 4 ns(6 ns)이므로 STA가 낙관적이 된다.

**스펙 근거.** 6.1.2.1 NOTE 1, 4.3.2, 4.4.2 (정보성): 호스트(ATE, 버스 컨트롤러)는 TMS와 TDI를 TCK 하강에서 바꾸는 것으로 가정한다.

**결정.** `set_input_delay -clock tck -clock_fall 4.0 [get_ports {tms tdi}]`로 바꾸고 CLAUDE.md §4도 수정한다. 출력 지연(`tdo`, `tdo_oe`)은 negedge 발사 → 상승 캡처의 반 주기 경로이므로 그대로 둔다.

**검증.** Genus/Innovus timing 리포트에서 `tms`/`tdi` → TCK posedge FF 경로의 launch edge가 fall인지 확인하고, 그 slack을 results.md에 기록한다.

---

## D-003 IDCODE `32'hDEADBEEF` 유지, 12.2.1 c 편차 (잠정, 2026-10-20)

**문제.** CLAUDE.md는 12.2.1 b(제조사 코드 `00001111111` 금지)만 확인했다. 그런데 12.2.1 c는 부품을 처음 생산할 때 소유하는 회사의 JEP106 코드를 쓰도록 요구한다. 본 프로젝트에는 할당받은 JEP106 코드가 없다.

**값.** version `0xD`, part `0xEADB`, manufacturer `[11:1]=0x777` (continuation 7개 → bank 8, ID 0x77), `[0]=1`. bank 8 / 0x77이 실제 회사에 할당돼 있는지는 확인하지 못했다(UNVERIFIED).

**결정(잠정).** 학습용이므로 `0xDEADBEEF`를 유지한다.
OpenOCD 완료 기준 (b)와도 일치한다. 실제 제품에 쓴다면 소유 회사 코드로 바꿔야 한다. 사용자 이의가 없으면 확정한다.

---

## D-004 시프트 레지스터도 `trst_n`으로 리셋 (확정, 2026-10-20)

**스펙 범위.** TLR에서 IR 시프트 단의 값은 미정의다(Table 7-1). bypass와 ID 레지스터도 Capture-DR 전에는 값이 정의되지 않는다. 따라서 리셋은 필수가 아니다.

**결정.** `tck_ir_sr_q`(리셋값 `00001`), `tck_bypass_q`(0), `tck_idcode_sr_q`(`IDCODE_VALUE`), `tck_tdo_q`(0)도 `trst_n`으로 비동기 리셋한다.
- 이유 1: GLS와 4-state 시뮬에서 X가 퍼지지 않게 한다.
- 이유 2: D-001의 설계 규칙(TLR+TMS=1에서 D = 리셋값)을 모든 FF에 대해 성립시킨다. TLR에서 이 레지스터들은 값을 유지하므로 D = Q = 리셋값이 된다.

**비용.** FF 41개에 리셋 핀이 붙는다. 면적 영향은 합성 후 results.md에 기록한다.

---

## D-005 1단계 `jtag_tap` 포트는 TAP 핀 6개만 (확정, 2026-10-20)

**결정.** 포트는 `tck`, `tms`, `tdi`, `trst_n`, `tdo`, `tdo_oe`만 둔다. 외부 DR 연결용 포트(상태 디코드 출력, IR 출력, 외부 TDO 입력)는 2단계 BSR을 붙일 때 추가하고, 그때 이 항목을 갱신한다.

**근거.** CLAUDE.md §7(한 단계 완료 전 다음 단계 선행 금지)과 lint 경고 0 기준 때문이다. 쓰지 않는 입력 포트를 두면 UNUSED 경고가 난다.

---

## D-006 GLS에서 S6c의 TRST* 해제 시점을 저위상 중간으로 변경 (확정, 2026-10-20)

**문제.** TB 시나리오 S6c는 D-001을 확인하려고 TRST* 해제를 TCK 상승과 **같은 시각**에 둔다(TMS=1).
- RTL에서는 PASS다.
- post-route GLS(Xcelium 23.09, SDF 2.1)에서는 그 순간 posedge FF들의 `$recovery`(RN/SN↑ → CK↑)와 removal(`$hold` CK↑ → RN/SN↑) 위반이 났다. max 코너 192건, min 코너 168건이 모두 t=217,578 ns 한 시각에 몰려 있었다.
- 셀 모델의 notifier가 Q를 X로 만들어 S6c가 80건 FAIL했다. 나머지 시나리오는 모두 PASS였다.

**분석.**
- 동시 해제는 정의상 recovery/removal 위반이다. STA에서도 `trst_n`은 false path로 검사 대상이 아니다(D-001).
- D-001의 안전 논거는 "TLR + TMS=1에서 D = 리셋값이므로, 위반으로 FF가 옛 값이든 새 값이든 같은 상태로 정착한다"이다. notifier 기반 셀 모델은 위반을 무조건 X로 처리하므로 이 논거를 표현할 수 없다.
- RTL 구조로 해결되는 문제도 아니다. 해제 동기화기를 넣어도 첫 단 FF가 같은 위반으로 X가 된다.

**선택지.**
- (a) GLS에서 해제 시점만 엣지에서 떨어뜨린다 ← 채택
- (b) GLS에서 S6c를 제외한다
- (c) 그대로 두고 완료 기준 (d)를 미충족으로 남긴다
- (사용자 선택: a, 2026-10-20)

**결정.**
- `tb/tb_tap.sv` S6c에 `ifdef GLS` 분기를 둔다. GLS에서는 TCK가 계속 도는 가운데 TMS=1 상태에서, TCK 하강 30 ns 뒤(다음 상승 20 ns 전) 저위상 중간에 해제한다.
- RTL 빌드는 동시 해제를 그대로 유지한다.
- 기대값(해제 후 TLR → IDCODE)과 다른 시나리오는 바꾸지 않는다.

**결과.** GLS max·min 모두 `ALL TESTS PASSED`, 타이밍 위반 0건(results.md 1.7).

**남는 위험(D-006).** 동시 해제 시 실리콘에서 실제로 같은 상태로 정착하는지는 GLS로 보이지 못한다. D-001의 설계 규칙(TLR + TMS=1에서 D = 리셋값)과 RTL S6c로만 뒷받침된다. 사용 조건(TCK 정지 중 또는 TMS=1 유지 중 해제)은 D-001대로 유지한다.

---

## D-007 공개 저장소에 라이브러리 파생물을 올리지 않음 (확정, 2026-10-20)

**문제.** 표준셀 라이브러리 gsclib045(Cadence GPDK045 기반)의 Software License Agreement(Design Materials)는 다음을 정한다(요약).
- 사용 범위: 평가·시연 목적, **조직 내부**로 한정
- 성격: Design Materials는 Cadence의 기밀·독점 정보
- 제한: Design Materials를 **전체든 일부든** 배포·복사·전송 금지

공개 저장소에 올린 산출물 중 일부는 라이브러리 데이터를 담고 있다.
- SDF: 라이브러리 특성화에서 나온 셀·배선 지연
- DEF: tech LEF에서 온 층·비아·트랙 정보
- 리포트: 셀별 지연·면적·전력
- 넷리스트: 셀 이름

법률 판단은 아니지만, 위 조항과 충돌할 소지가 크다고 봤다.

**결정(사용자 선택, 2026-10-20).**
- `syn/out/`, `syn/rpt/`, `pnr/out/`, `pnr/rpt/`를 저장소에서 빼고 `.gitignore`에 넣는다.
- 문서에서 라이브러리 내부 수치(셀 면적·LEF 크기 대조값)와 특성화 방식 설명을 지운다.
- 공개 히스토리를 다시 써서 force push한다.
- 저장소에는 직접 작성한 RTL, TB, 시뮬 코드, 스크립트, 문서와 요약 PPA 수치(WNS, 총 면적, 셀·FF 수, 전력)만 둔다.

**남는 확인.**
- 학교의 Cadence University Program 계약 조건이 다를 수 있으므로, 교수님이나 서버 관리자에게 최종 확인한다.
- force push 이전 커밋은 GitHub에서 참조가 끊기지만 SHA로 한동안 접근될 수 있다. 완전 삭제가 필요하면 GitHub 지원에 캐시 정리를 요청한다.
