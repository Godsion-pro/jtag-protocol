# spec_notes.md — 스펙 조항 요약

- 출처: IEEE Std 1149.1-2013, 로컬 사본 `docs/ref/11491-2013(JTAG).pdf` (기관 라이선스, 재배포 금지).
- 원칙: 조항 번호 + 요약(의역)만 기록하고 원문은 옮기지 않는다. 쪽수는 인쇄 쪽수.
- 확인일: 2026-10-20. 표기: (R)=Rule, (Rec)=Recommendation, (P)=Permission, (N)=NOTE/Description(정보성, 요구사항 아님).
- `UNVERIFIED`: 로컬 원문으로 확인하지 못했거나 CLAUDE.md와 해석이 갈리는 항목. 해결 전에는 구현에 반영하지 않는다.

---

## 1. 1단계 핵심 4개 조항

### 6.1.2.1 TAP controller operation (p.30, Table 6-2 p.33)

| 항 | 종류 | 요약 | jtag_tap.v 반영 |
|---|---|---|---|
| a | R | TAP 상태는 세 가지 사건에서만 바뀐다: TCK 상승 엣지, TRST* 입력의 0 전이(있을 때), 전원 인가. | `tck_state_q`: `posedge tck or negedge trst_n`만 사용 |
| b | R | TAP는 IR·TDR 및 관련 회로의 제어 신호를 만든다 (Fig. 6-3, 6-4). | 상태 디코드 신호 |
| b NOTE 1 | N | 그림은 TMS/TDI가 TCK 하강에서 바뀐다고 가정한다. ID 레지스터가 있으면 TLR에서 IR 출력이 IDCODE, 없으면 BYPASS. | TB는 TMS/TDI를 TCK 하강 후에 구동 |
| c | R | TDO 출력 버퍼와 TDO로 보낼 레지스터 선택은 Table 6-2를 따른다. | `tdo` 소스 mux, `tdo_oe` |
| d | R | Table 6-2의 TDO 변화는 해당 상태에 들어간 뒤의 **TCK 하강 엣지**에서 일어난다. | `tdo_q`, `tdo_oe_q`는 negedge FF |
| d NOTE 2 | N | TDO 드라이버 활성 구간은 표에 적힌 상태의 첫 하강 엣지부터, 그 상태를 떠난 뒤 첫 하강 엣지까지다. 즉 상태보다 반 주기 늦다. | TB의 `tdo_oe` 구간 검사 기준 |

Table 6-2 요약:

| 상태 | TDO로 나가는 레지스터 | TDO 드라이버 |
|---|---|---|
| Shift-IR | 명령 레지스터 | 활성 |
| Shift-DR | 현재 명령이 선택한 TDR | 활성 |
| 나머지 14개 상태 | 미정의 | 비활성 |

구현 해석 (1단계):
- `tdo_oe_d = (state == SHIFT_IR) || (state == SHIFT_DR)`를 negedge에서 래치.
- `tdo_d`: Shift-IR이면 IR 시프트 레지스터 LSB, Shift-DR이면 선택된 DR의 LSB, 그 외 상태는 이전 값 유지(비활성 구간의 값은 스펙상 미정의, TB는 검사하지 않음).

### 7.1.1 Instruction register 설계 (p.46) + 7.2.1 동작 (p.47)

| 항 | 종류 | 요약 | 반영 |
|---|---|---|---|
| 7.1.1 a | R | IR은 시프트 레지스터 기반 셀을 최소 2개 가진다. | IR 길이 5 |
| 7.1.1 b | R | 명령의 효과가 바뀌는 시점은 Update-IR과 Test-Logic-Reset 상태로 한정된다 (래치된 병렬 출력). | IR 시프트부(`tck_ir_sr_q`)와 출력 홀드부(`tck_ir_q`) 분리 |
| 7.1.1 c | R | IR 직렬 입력→출력 경로에서 데이터가 반전되지 않는다. | TB: IR 관통 시프트 검사 |
| 7.1.1 d | R | TDO에 가장 가까운 하위 2셀은 Capture-IR에서 고정 패턴 `01`을 로드한다 (LSB가 1). | Capture-IR 값 `5'b00001` |
| 7.1.1 e | Rec | 설계 정보를 담지 않는 나머지 셀도 Capture-IR에서 고정값(0/1)을 로드하는 것이 좋다. | 상위 3비트 `000` 고정 |
| 7.1.1 f | P | 하위 2셀 외의 셀에는 설계 정보 병렬 입력을 둘 수 있다. | 사용 안 함 |
| 7.1.2 | N | `01` 패턴은 보드 직렬 경로 고장 격리용이다. 고정 캡처값은 BSDL에 기록 권장. SAMPLE/PRELOAD 코드 공유는 과거판에서 쓰던 방식. | 2단계 BSDL `INSTRUCTION_CAPTURE` |
| 7.2.1 c | R | 시프트 레지스터 단의 모든 동작은 상태 진입 후 TCK 상승 엣지에서 일어난다. | `tck_ir_sr_q`는 posedge |
| 7.2.1 d | R | IR 병렬 출력은 Update-IR 상태의 **TCK 하강 엣지**에 시프트 레지스터 값으로 래치된다. | `tck_ir_q`는 negedge |
| 7.2.1 e | R | 클럭 동작으로 TLR에 들어가면, 그 뒤 TCK 하강 엣지에서 IR 출력이 IDCODE(ID 레지스터가 없으면 BYPASS)로 래치된다. | TLR에서 negedge에 `IR_IDCODE` 로드 |
| 7.2.1 f | R | TRST*에 low가 가해지면 래치된 명령이 비동기로 IDCODE(없으면 BYPASS)가 된다. | `tck_ir_q` 비동기 리셋값 = `IR_IDCODE` |

Table 7-1 요약 (`pdftotext -layout`이 Pause-IR/Update-IR 행을 어긋나게 추출해서 `-raw` 출력으로 다시 확인함):

| 상태 | 시프트 레지스터 단 | 병렬 출력 |
|---|---|---|
| Test-Logic-Reset | 미정의 | IDCODE(또는 BYPASS)로 리셋 |
| Capture-IR | TDO 쪽 2비트에 `01`, 나머지는 선택적으로 설계 정보 또는 고정값 | 유지 |
| Shift-IR | 직렬 출력 방향으로 시프트 | 유지 |
| Exit1-IR / Pause-IR / Exit2-IR | 유지 | 유지 |
| Update-IR | 유지 | 시프트 레지스터 값 로드 |
| 그 외 모든 상태 | 미정의 | 유지 |

### 8.4.1 BYPASS 명령 (p.53) + 10.1.1 Bypass 레지스터 (p.116)

| 항 | 종류 | 요약 | 반영 |
|---|---|---|---|
| 8.4.1 a | R | 모든 부품은 BYPASS 명령을 제공한다. | 필수 |
| 8.4.1 b | R | BYPASS 코드는 IR 전 비트가 1인 값이다. | `5'h1F` |
| 8.4.1 c | R | BYPASS는 Shift-DR에서 bypass 레지스터를 TDI–TDO 사이에 연결한다. | DR mux |
| 8.4.1 d | R | BYPASS 중 시스템/테스트 겸용 TDR은 시스템 기능을 수행한다. | 1단계 해당 TDR 없음 (2단계 BSR에 적용) |
| 8.4.1 e | R | TMP 컨트롤러가 없거나 Persistence-Off이면, BYPASS 중 테스트 로직은 시스템 로직이나 핀–코어 신호 흐름에 영향을 주지 않는다. | 본 설계는 TMP 없음 |
| 8.4.1 f | P | BYPASS에 all-1 외의 코드를 추가로 줄 수 있다. | `5'h00` 추가 |
| 8.4.1 g | Rec | all-0 코드도 BYPASS로 두는 것이 좋다. | `5'h00` = BYPASS |
| 10.1.1 a | R | bypass 레지스터는 시프트 레지스터 1단이다. | `tck_bypass_q` 1비트 |
| 10.1.1 b | R | 현재 명령이 bypass를 선택하면 Capture-DR의 TCK 상승 엣지에서 0으로 세트된다. | TB: 첫 출력 비트 0 |
| 10.1.1 c, d | R | bypass 단은 시스템 기능에 쓰지 않는 전용 회로이며 시스템 로직에 영향이 없다. | 전용 FF |

### 8.13.1 IDCODE 명령 (p.70) + 12장 Device ID 레지스터 (p.166–168)

| 항 | 종류 | 요약 | 반영 |
|---|---|---|---|
| 8.13.1 a | R | ID 레지스터가 있으면 IDCODE 명령을 제공한다. | 제공 |
| 8.13.1 b | R | IDCODE는 Shift-DR에서 ID 레지스터 **하나만** TDI–TDO 사이에 연결한다 (다른 TDR 직렬 연결 금지). | DR 길이 정확히 32 (TB 검사) |
| 8.13.1 c | R | IDCODE 선택 시 Capture-DR 진입 후 TCK 상승 엣지에서 ID 코드가 ID 레지스터에 로드된다. | `tck_idcode_sr_q` posedge 캡처 |
| 8.13.1 d, e | R | BYPASS와 같이 시스템 기능과 핀 신호 흐름에 영향이 없다 (TMP 없음 기준). | — |
| 8.13.1 f | P | IDCODE 코드값은 설계자가 정한다. | `5'h01` (RISC-V Debug, 3절 참조) |
| 8.13.2 | N | TLR에서 IDCODE가 IR 출력으로 강제되므로 TMS/TCK만으로 보드 위 부품을 식별(blind interrogation)할 수 있다. | TB 시나리오 1, 10 |
| 12.1.1 a | R | ID 레지스터는 병렬 입력만 있고 병렬 출력은 없는 시프트 경로다. | — |
| 12.1.1 c | R | Capture-DR의 TCK 상승에서 이후 시프트로 ID 코드가 TDO로 나가도록 세트된다. | — |
| 12.1.1 d | R | 공급자 정의 ID 코드는 4개 필드를 가진다 (Fig. 12-1: version / part number / manufacturer / LSB). | — |
| 12.1.2 | N | ID 레지스터는 LSB에 상수 1을 로드하고 bypass는 0을 로드하므로, TLR 직후 DR 스캔의 첫 비트로 ID 레지스터 유무를 구분할 수 있다. | TB: 첫 출력 비트 1 |
| 12.2.1 a | R | 11비트 제조사 코드 = JEP106 압축형. bits 7–1은 JEP106 마지막 바이트(패리티 제외), bits 11–8은 continuation(0x7F) 바이트 개수(16 초과 시 mod 16). | — |
| 12.2.1 b | R | 제조사 코드 `00001111111`은 사용 금지. | 0x777이므로 충족 |
| 12.2.1 c | R | 제조사 코드는 부품을 처음 생산할 때 소유·지원하는 회사의 코드여야 한다. | **UNVERIFIED-3 참조** |

`32'hDEADBEEF` 분해: version `[31:28]=0xD`, part `[27:12]=0xEADB`, manufacturer `[11:1]=0x777` (continuation 7개 → bank 8, ID 0x77), `[0]=1`.

---

## 2. 관련 조항 (TAP 핀, 상태도, 초기화, 명령 일반)

| 조항 | 요약 | 반영 |
|---|---|---|
| 4.1.1 a | TAP 연결은 TCK, TMS, TDI, TDO. | 포트 |
| 4.1.1 b | 전원 인가 후 TAP 상태가 외부 제어 없이 불확정이면 TRST*가 필요하다. | POR 없음 → `trst_n` 필수 |
| 4.1.1 c | TAP 핀은 다른 용도로 쓰지 않는 전용 핀. | — |
| 4.2.1 a (R) / c (P) | TCK를 0에 멈추면 테스트 로직의 저장 소자는 상태를 무기한 유지해야 한다. 1에 멈춘 경우의 유지는 선택 사항. | 정적 FF만 사용 |
| 4.3.1 a, b | TMS는 TCK 상승에서 샘플링. 구동되지 않은 TMS는 1로 동작해야 한다. | 풀업은 패드 레벨 (2단계 패드 결정 시) |
| 4.4.1 a, b, c | TDI는 TCK 상승에서 샘플링. 비구동 TDI는 1로 동작. TDI 데이터는 선택된 레지스터 길이만큼 지난 뒤 반전 없이 TDO에 나타난다. | TB 관통 검사 |
| 4.5.1 a | TDO 변화는 TCK 하강 엣지, 또는 TRST*의 하강 엣지에서만 일어난다. | TB 엣지 검사기에서 TRST* 하강도 허용 |
| 4.5.1 b | 데이터 시프트 중이 아니면 TDO 드라이버는 비활성. | `tdo_oe` |
| 4.6.1 a | TRST*에 0이 가해지면 TAP는 비동기로 TLR에 리셋된다 (NOTE: 다른 테스트 로직도 TLR 요구 상태로 비동기 리셋). | 모든 TCK 도메인 FF의 비동기 리셋 |
| 4.6.1 b | 비구동 TRST*는 1로 동작. | 패드 레벨 |
| 4.6.1 c | TRST*로 시스템 로직을 초기화하지 않는다. | `trst_n`은 TCK 도메인 전용 |
| 4.6.1 e (Rec) | TRST*가 0→1로 바뀌는 동안 TMS를 1로 유지하는 것이 좋다. | **UNVERIFIED-1 참조** |
| 6.1.1.1 a, b | 상태도는 Fig. 6-1 (16 상태)을 따르고, 모든 전이는 TCK 상승 시점의 TMS 값으로 결정된다. | FSM, TB 참조 모델 |
| 6.1.1.1 c | 테스트 로직 동작은 각 상태에서 Fig. 6-2에 정의된 상승/하강 엣지에서 일어난다. | — |
| 6.1.1.2 (N) | 어떤 상태에서든 TMS=1로 상승 엣지 5번이면 TLR에 들어가고, TMS=1인 동안 머문다. TLR을 떠나면 RTI로 간다. | TB 시나리오 5 |
| 6.1.3.1 a | 전원 인가 시 TRST* 또는 내장 회로로 TLR에 강제 진입. | `trst_n` |
| 6.1.3.1 b | 시스템 리셋 같은 시스템 입력으로 TAP를 초기화하면 안 된다. | 3단계 `rst_n`은 TCK 도메인에 연결 금지 |
| 6.1.3.1 c | TRST* 초기화는 클럭과 무관하게 TRST*가 low로 바뀔 때 비동기로 일어난다. | 비동기 리셋 |
| 8.1.1 c | 각 명령은 Shift-DR에서 TDI–TDO 사이에 직렬 경로 하나만 선택한다. | DR mux |
| 8.1.1 d | 별도 기능이 없는 명령 코드는 BYPASS와 동일하게 동작한다. | 1단계: `5'h01` 외 전 코드 → BYPASS |
| 8.1.1 e | 명령에 따른 동작은 Update-IR 또는 TLR에서 다른 명령이 IR 출력으로 옮겨질 때 끝난다. | — |
| 8.1.1 f (Rec) | 정상 동작을 방해하는 명령에는 all-0 코드를 쓰지 않는 것이 좋다 (TDI stuck-at-0 대비). | 2단계 EXTEST = `5'h04` |
| 8.1.1 h (P) | 각 명령의 규칙을 모두 지키면 두 명령이 한 코드를 공유할 수 있다. | 2단계 SAMPLE/PRELOAD `5'h02` |

---

## 3. IEEE 1149.1 외 출처 (docs/ref에 원문 없음)

| 항목 | CLAUDE.md 값 | 출처 | 상태 |
|---|---|---|---|
| IR 길이 | 5 | RISC-V Debug Spec §6.1 | UNVERIFIED (로컬 사본 없음) |
| IDCODE 코드 / 리셋값 | `5'h01` | RISC-V Debug Spec §6.1 | UNVERIFIED (로컬 사본 없음) |
| dtmcs / dmi | `5'h10` / `5'h11` | RISC-V Debug Spec §6.1 | 3단계. 1단계에서는 미할당 → BYPASS (8.1.1 d) |
| reserved | `5'h12`–`5'h17` | RISC-V Debug Spec §6.1 | BYPASS |

1단계 BYPASS 대상 코드: `5'h01`을 제외한 31개 전부. 2단계(`5'h02`, `5'h04`)와 3단계(`5'h10`, `5'h11`)에서 TB 기대값 표를 바꿔야 한다.

---

## 4. UNVERIFIED / 결정 이력

- ~~UNVERIFIED-1 — TRST* 해제 정책~~ → **해결: decisions.md D-001.** 동기화기 없이 직접 비동기 리셋을 쓴다. 해제 조건은 4.6.1 e를 따르고, TLR+TMS=1에서 D가 리셋값과 같도록 설계한다. 업계 사례 조사도 D-001에 있다.
- ~~UNVERIFIED-2 — SDC 입력 지연 기준 엣지~~ → **해결: decisions.md D-002.** `-clock_fall`을 추가했다.
- **UNVERIFIED-3 — IDCODE 제조사 코드.** decisions.md D-003에 잠정 편차로 기록했다. bank 8 / 0x77의 실제 JEP106 할당 여부는 여전히 확인하지 못했다.
- **UNVERIFIED-4 — RISC-V Debug Spec 원문.** IR 길이 5와 IDCODE 코드 `5'h01`은 RISC-V Debug Spec §6.1이 출처인데 docs/ref에 사본이 없다(3절). 원문을 구하면 대조한다.
