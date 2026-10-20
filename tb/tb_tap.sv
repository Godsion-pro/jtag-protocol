`timescale 1ns/1ps
// tb/tb_tap.sv — Stage 1 testbench for rtl/jtag_tap.v (IEEE 1149.1-2013 TAP, IR 5-bit, BYPASS, IDCODE).
//
// RTL/GLS shared: only DUT ports are observed (no hierarchical references into the DUT).
// Expected values are derived from the spec clauses cited per scenario (docs/spec_notes.md), never
// from the RTL. A reference TAP FSM (Fig. 6-1) clocked by the same TMS supplies the expected tdo_oe
// (Table 6-2 + NOTE 2) and the TAP arc coverage (16 states x 2 TMS values = 32 arcs).
//
// Scenarios (docs plan, section 4):
//   S1 IDCODE after reset          S6 TRST* asynchronous reset
//   S2 Capture-IR "01"             S7 Pause/Exit2 continuity
//   S3 BYPASS 1-bit delay, capt 0  S8 tdo_oe window
//   S4 unassigned IR -> BYPASS     S9 TDO changes only on TCK falling edge
//   S5 TMS=1 x5 -> TLR from all 16 states   S10 3-TAP chain
// Always-on monitors: tdo_oe vs. reference model at every TCK edge, TDO/tdo_oe edge checker.
// Last line: "ALL TESTS PASSED" or "N FAILURES" (non-zero exit on failure).
// GLS: compile with GLS defined (plus GLS_MIN for fast-corner delays) against the post-route netlist,
// see gls/run_gls.sh.

module tb_tap;

    // ------------------------------------------------------------------ timing
    localparam real T_HALF = 50.0;      // TCK = 10 MHz
    localparam real T_DRV  = 10.0;      // host drives TMS/TDI this long after TCK falls
    localparam real T_SMP  = 5.0;       // host samples TDO this long before TCK rises
    localparam real T_CHK  = 7.0;       // tdo_oe monitor samples this long after each TCK edge
`ifdef GLS
    localparam real TDO_DLY_MAX = 5.0;  // allowed TCK/TRST* fall -> tdo/tdo_oe delay (< T_CHK, T_DRV)
`else
    localparam real TDO_DLY_MAX = 0.0;
`endif
    localparam real TIMEOUT = 20.0e6;   // 20 ms watchdog
    localparam int  MAXB    = 128;

    // ------------------------------------------------------------------ spec-derived constants
    localparam int          IR_LEN         = 5;              // RISC-V Debug §6.1 (>= 2: 7.1.1 a)
    localparam logic [4:0]  IR_CAPTURE_EXP = 5'b00001;       // 7.1.1 d (LSBs "01"), e (other bits fixed 0)
    localparam logic [4:0]  IR_BYPASS0     = 5'h00;          // 8.4.1 g (recommended all-0 BYPASS)
    localparam logic [4:0]  IR_IDCODE      = 5'h01;          // 8.13.1 f, RISC-V Debug §6.1
    localparam logic [4:0]  IR_BYPASS      = 5'h1F;          // 8.4.1 b (all-1)
    localparam logic [31:0] IDCODE_EXP     = 32'hDEADBEEF;   // CLAUDE.md §3, decisions.md D-003
    localparam logic [31:0] TDI_PAT        = 32'hA5A5_5A5A;  // arbitrary data pushed through the ID register
    localparam logic [7:0]  BYP_DIN        = 8'b0100_1101;   // TDI 1,0,1,1,0,0,1,0 (LSB first)
    localparam logic [7:0]  BYP_SPLIT_DIN  = 8'b0110_0101;   // TDI 1,0,1,0,0,1,1,0 (LSB first; bit 2 != bit 3)

    // ------------------------------------------------------------------ reference model state codes
    localparam logic [3:0] S_TLR     = 4'd0,  S_RTI     = 4'd1,
                           S_SELDR   = 4'd2,  S_CAPDR   = 4'd3,  S_SHDR    = 4'd4,  S_EX1DR   = 4'd5,
                           S_PAUSEDR = 4'd6,  S_EX2DR   = 4'd7,  S_UPDDR   = 4'd8,
                           S_SELIR   = 4'd9,  S_CAPIR   = 4'd10, S_SHIR    = 4'd11, S_EX1IR   = 4'd12,
                           S_PAUSEIR = 4'd13, S_EX2IR   = 4'd14, S_UPDIR   = 4'd15;

    // ------------------------------------------------------------------ host signals and DUTs
    logic tck       = 1'b0;
    logic tms       = 1'b1;
    logic tdi       = 1'b1;
    logic trst_n    = 1'b1;
    logic sel_chain = 1'b0;   // 0: observe the single TAP, 1: observe the end of the 3-TAP chain
    logic chk_en    = 1'b0;   // monitors armed

    wire dut_tdo, dut_oe;
    wire c0_tdo, c0_oe, c1_tdo, c1_oe, c2_tdo, c2_oe;

    wire [3:0] all_tdo = {c2_tdo, c1_tdo, c0_tdo, dut_tdo};
    wire [3:0] all_oe  = {c2_oe,  c1_oe,  c0_oe,  dut_oe};
    wire       tdo_obs = sel_chain ? c2_tdo : dut_tdo;
    wire       oe_obs  = sel_chain ? c2_oe  : dut_oe;

    // RTL: jtag_tap. GLS: the post-route netlist top kh_jtag_top (same ports), because the SDF's
    // DESIGN is kh_jtag_top. Expectations and scenarios are identical in both cases.
`ifdef GLS
    `define KH_TAP kh_jtag_top
`else
    `define KH_TAP jtag_tap
`endif

    `KH_TAP u_dut (.tck(tck), .tms(tms), .tdi(tdi),    .trst_n(trst_n), .tdo(dut_tdo), .tdo_oe(dut_oe));

    // 3-TAP chain for S10: TDI -> u_c0 -> u_c1 -> u_c2 -> TDO, shared TCK/TMS/TRST*.
    `KH_TAP u_c0  (.tck(tck), .tms(tms), .tdi(tdi),    .trst_n(trst_n), .tdo(c0_tdo),  .tdo_oe(c0_oe));
    `KH_TAP u_c1  (.tck(tck), .tms(tms), .tdi(c0_tdo), .trst_n(trst_n), .tdo(c1_tdo),  .tdo_oe(c1_oe));
    `KH_TAP u_c2  (.tck(tck), .tms(tms), .tdi(c1_tdo), .trst_n(trst_n), .tdo(c2_tdo),  .tdo_oe(c2_oe));

`ifdef GLS
    // SDF back-annotation of every TAP instance. GLS_MIN selects the fast-corner (min) delays,
    // otherwise the slow-corner (max) delays. GLS_SDF overrides the SDF path.
`ifndef GLS_SDF
    `define GLS_SDF "pnr/out/kh_jtag_top.pnr.sdf"
`endif
`ifdef GLS_MIN
    `define GLS_MTM "MINIMUM"
`else
    `define GLS_MTM "MAXIMUM"
`endif
    initial begin
        $sdf_annotate(`GLS_SDF, u_dut, , , `GLS_MTM);
        $sdf_annotate(`GLS_SDF, u_c0,  , , `GLS_MTM);
        $sdf_annotate(`GLS_SDF, u_c1,  , , `GLS_MTM);
        $sdf_annotate(`GLS_SDF, u_c2,  , , `GLS_MTM);
    end
`endif

    `include "jtag_drv.svh"

    // ------------------------------------------------------------------ reference TAP model (Fig. 6-1)
    logic [3:0]  m_state;
    logic        m_oe;
    logic [31:0] arc_hit = 32'd0;   // index {state, tms}

    function automatic logic [3:0] tap_next(input logic [3:0] s, input logic t);
        case (s)
            S_TLR:     return t ? S_TLR   : S_RTI;
            S_RTI:     return t ? S_SELDR : S_RTI;
            S_SELDR:   return t ? S_SELIR : S_CAPDR;
            S_CAPDR:   return t ? S_EX1DR : S_SHDR;
            S_SHDR:    return t ? S_EX1DR : S_SHDR;
            S_EX1DR:   return t ? S_UPDDR : S_PAUSEDR;
            S_PAUSEDR: return t ? S_EX2DR : S_PAUSEDR;
            S_EX2DR:   return t ? S_UPDDR : S_SHDR;
            S_UPDDR:   return t ? S_SELDR : S_RTI;
            S_SELIR:   return t ? S_TLR   : S_CAPIR;
            S_CAPIR:   return t ? S_EX1IR : S_SHIR;
            S_SHIR:    return t ? S_EX1IR : S_SHIR;
            S_EX1IR:   return t ? S_UPDIR : S_PAUSEIR;
            S_PAUSEIR: return t ? S_EX2IR : S_PAUSEIR;
            S_EX2IR:   return t ? S_UPDIR : S_SHIR;
            S_UPDIR:   return t ? S_SELDR : S_RTI;
            default:   return S_TLR;
        endcase
    endfunction

    function automatic string sname(input logic [3:0] s);
        case (s)
            S_TLR:     return "Test-Logic-Reset";
            S_RTI:     return "Run-Test/Idle";
            S_SELDR:   return "Select-DR-Scan";
            S_CAPDR:   return "Capture-DR";
            S_SHDR:    return "Shift-DR";
            S_EX1DR:   return "Exit1-DR";
            S_PAUSEDR: return "Pause-DR";
            S_EX2DR:   return "Exit2-DR";
            S_UPDDR:   return "Update-DR";
            S_SELIR:   return "Select-IR-Scan";
            S_CAPIR:   return "Capture-IR";
            S_SHIR:    return "Shift-IR";
            S_EX1IR:   return "Exit1-IR";
            S_PAUSEIR: return "Pause-IR";
            S_EX2IR:   return "Exit2-IR";
            S_UPDIR:   return "Update-IR";
            default:   return "?";
        endcase
    endfunction

    // State changes only on TCK rise or TRST* fall (6.1.2.1 a); TRST* forces Test-Logic-Reset (4.6.1 a).
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            m_state <= S_TLR;
        end else begin
            arc_hit[{m_state, tms}] <= 1'b1;
            m_state <= tap_next(m_state, tms);
        end
    end

    // TDO driver active from the first falling edge in Shift-IR/Shift-DR to the first falling edge
    // after leaving it (6.1.2.1 d + NOTE 2, Table 6-2).
    always @(negedge tck or negedge trst_n) begin
        if (!trst_n) m_oe <= 1'b0;
        else         m_oe <= (m_state == S_SHDR) || (m_state == S_SHIR);
    end

    // ------------------------------------------------------------------ always-on monitors
    int errors   = 0;   // scenario checks
    int err_oe   = 0;   // tdo_oe monitor
    int err_edge = 0;   // TDO edge checker

    // tdo_oe of every TAP matches the model T_CHK after each TCK edge (Table 6-2, NOTE 2).
    initial forever begin
        @(tck);
        #(T_CHK);
        if (chk_en && (all_oe !== {4{m_oe}})) begin
            err_oe++;
            if (err_oe <= 10)
                $display("  FAIL [oe] t=%0t tck=%b model=%s exp=%b got(c2,c1,c0,dut)=%b",
                         $realtime, tck, sname(m_state), m_oe, all_oe);
        end
    end

    // tdo / tdo_oe of every TAP change only on a TCK falling edge or a TRST* falling edge (4.5.1 a,
    // 6.1.2.1 d), within TDO_DLY_MAX.
    initial forever begin
        @(all_tdo or all_oe);
        if (chk_en && (($realtime - t_tck_fall) > TDO_DLY_MAX) && (($realtime - t_trst_fall) > TDO_DLY_MAX)) begin
            err_edge++;
            if (err_edge <= 10)
                $display("  FAIL [edge] t=%0t tdo(c2,c1,c0,dut)=%b oe=%b, last TCK fall %0t, last TRST* fall %0t",
                         $realtime, all_tdo, all_oe, t_tck_fall, t_trst_fall);
        end
    end

    // ------------------------------------------------------------------ check helpers
    string sc_title;
    int    sc_err0;
    bits_t acc;   // TDO bits collected by hand-written scan sequences (LSB = first bit)

    function automatic int total_errors();
        return errors + err_oe + err_edge;
    endfunction

    task automatic fail(input string msg);
        errors++;
        $display("  FAIL: %s", msg);
    endtask

    task automatic check_bits(input string what, input bits_t got, input bits_t exp, input int n);
        bits_t m;
        m = (n >= MAXB) ? {MAXB{1'b1}} : (({{(MAXB-1){1'b0}}, 1'b1} << n) - 1'b1);
        if ((got & m) !== (exp & m)) begin
            errors++;
            $display("  FAIL: %s (%0d bits, bit 0 = first)", what, n);
            $display("        got %h", got & m);
            $display("        exp %h", exp & m);
        end
    endtask

    task automatic check_bit(input string what, input logic got, input logic exp);
        if (got !== exp) begin
            errors++;
            $display("  FAIL: %s: got %b exp %b", what, got, exp);
        end
    endtask

    task automatic sc_begin(input string title);
        sc_title = title;
        sc_err0  = total_errors();
        $display("[%s]", sc_title);
    endtask

    task automatic sc_end();
        if (total_errors() == sc_err0) $display("[%s] PASS", sc_title);
        else                           $display("[%s] FAIL (%0d)", sc_title, total_errors() - sc_err0);
    endtask

    task automatic acc_clear();
        acc = '0;
    endtask

    task automatic acc_push();
        acc = {last_tdo, acc[MAXB-1:1]};
    endtask

    // TRST* reset, then Test-Logic-Reset -> Run-Test/Idle.
    task automatic reset_to_rti();
        trst_pulse();
        tick(1'b0, 1'b1);
    endtask

    // IR scan of the single TAP; every load also checks the Capture-IR pattern (7.1.1 d, e).
    task automatic load_ir(input logic [4:0] code);
        bits_t dout;
        shift_ir(`ZX(5, code), IR_LEN, dout);
        check_bits($sformatf("Capture-IR pattern while loading IR=0x%02h", code), dout, `ZX(5, IR_CAPTURE_EXP), IR_LEN);
    endtask

    // BYPASS path: Capture-DR loads 0, then TDI appears one bit later, uninverted
    // (8.4.1 c, 10.1.1 a, b, 4.4.1 c).
    task automatic check_bypass(input string what);
        bits_t dout;
        shift_dr(`ZX(8, BYP_DIN), 8, dout);
        check_bits(what, dout, `ZX(8, {BYP_DIN[6:0], 1'b0}), 8);
    endtask

    // IDCODE path: device ID loaded in Capture-DR, shifted out LSB first (8.13.1 b, c, 12.1.1 c).
    task automatic check_idcode(input string what);
        bits_t dout;
        shift_dr('0, 32, dout);
        check_bits(what, dout, `ZX(32, IDCODE_EXP), 32);
    endtask

    // Shortest TMS path from Run-Test/Idle to state t (time order = left to right). IR-side paths
    // shift TDI = 1 through Shift-IR so that a later Update-IR loads BYPASS, not the capture pattern.
    task automatic nav_path(input logic [3:0] t, output logic [31:0] seq, output int len);
        case (t)
            S_TLR:     begin seq = 32'b111;           len = 3;  end
            S_RTI:     begin seq = 32'b0;             len = 0;  end
            S_SELDR:   begin seq = 32'b1;             len = 1;  end
            S_CAPDR:   begin seq = 32'b10;            len = 2;  end
            S_SHDR:    begin seq = 32'b100;           len = 3;  end
            S_EX1DR:   begin seq = 32'b101;           len = 3;  end
            S_PAUSEDR: begin seq = 32'b1010;          len = 4;  end
            S_EX2DR:   begin seq = 32'b10101;         len = 5;  end
            S_UPDDR:   begin seq = 32'b1011;          len = 4;  end
            S_SELIR:   begin seq = 32'b11;            len = 2;  end
            S_CAPIR:   begin seq = 32'b110;           len = 3;  end
            S_SHIR:    begin seq = 32'b1100_00000;    len = 9;  end
            S_EX1IR:   begin seq = 32'b1100_00001;    len = 9;  end
            S_PAUSEIR: begin seq = 32'b1100_00001_0;  len = 10; end
            S_EX2IR:   begin seq = 32'b1100_00001_01; len = 11; end
            S_UPDIR:   begin seq = 32'b1100_00001_1;  len = 10; end
            default:   begin seq = 32'b0;             len = 0;  end
        endcase
    endtask

    // ------------------------------------------------------------------ scenarios

    // S1: Test-Logic-Reset selects IDCODE; the ID register is exactly 32 bits, LSB = 1.
    // 7.2.1 e, f; 8.13.1 b, c; 12.1.1 c; 12.1.2; 12.2.1 b; 4.4.1 c
    task automatic s1_idcode_after_reset();
        bits_t dout;
        sc_begin("S1 IDCODE after reset");
        // (a) TRST* only
        reset_to_rti();
        shift_dr(`ZX(32, TDI_PAT), 64, dout);
        check_bits("S1a 64-bit DR scan after TRST*: IDCODE, then TDI unchanged", dout, `ZX(64, {TDI_PAT, IDCODE_EXP}), 64);
        check_bit("S1a first ID bit is 1 (12.1.2)", dout[0], 1'b1);
        if (dout[11:1] === 11'b000_0111_1111) fail("S1a manufacturer code 00001111111 is forbidden (12.2.1 b)");
        // (b) TMS-only reset after selecting BYPASS: only Test-Logic-Reset can restore IDCODE
        load_ir(IR_BYPASS);
        check_bypass("S1b BYPASS selected before TMS reset");
        reset_tms();
        tick(1'b0, 1'b1);
        shift_dr(`ZX(32, TDI_PAT), 64, dout);
        check_bits("S1b 64-bit DR scan after TMS=1 x5: IDCODE, then TDI unchanged", dout, `ZX(64, {TDI_PAT, IDCODE_EXP}), 64);
        sc_end();
    endtask

    // S2: Capture-IR loads 00001; the IR is 5 bits, uninverted. 7.1.1 a, c, d, e; Table 7-1; 7.2.1 d
    task automatic s2_capture_ir();
        bits_t dout;
        sc_begin("S2 Capture-IR 01");
        reset_to_rti();
        // TDI (time order) 1,0,1,1,0 then 1,1,1,1,1
        shift_ir(`ZX(10, {5'b11111, 5'b01101}), 10, dout);
        check_bits("S2 10-bit IR scan: 00001 captured, then first 5 TDI bits", dout, `ZX(10, {5'b01101, IR_CAPTURE_EXP}), 10);
        check_bypass("S2 last 5 TDI bits (11111) latched at Update-IR -> BYPASS");
        sc_end();
    endtask

    // S3: BYPASS = 1-bit register, captures 0. 8.4.1 a, b, c, g; 10.1.1 a, b
    task automatic s3_bypass();
        sc_begin("S3 BYPASS 1-bit delay, capture 0");
        reset_to_rti();
        load_ir(IR_BYPASS);
        check_bypass("S3 IR=0x1F");
        load_ir(IR_BYPASS0);
        check_bypass("S3 IR=0x00");
        sc_end();
    endtask

    // S4: every opcode except IDCODE behaves as BYPASS in stage 1. 8.1.1 c, d; 8.4.1 f
    task automatic s4_unassigned_ir();
        logic [5:0] c;
        sc_begin("S4 unassigned IR -> BYPASS");
        reset_to_rti();
        for (c = 6'd0; c < 6'd32; c = c + 6'd1) begin
            load_ir(c[4:0]);
            if (c[4:0] == IR_IDCODE) check_idcode($sformatf("S4 IR=0x%02h selects IDCODE", c));
            else                     check_bypass($sformatf("S4 IR=0x%02h selects BYPASS", c));
        end
        sc_end();
    endtask

    // S5: TMS=1 for 5 rising edges reaches Test-Logic-Reset from every state. With IR=BYPASS before
    // the walk, reading IDCODE afterwards shows TLR was entered (7.2.1 e). From Capture-IR the walk
    // passes Update-IR with the capture pattern 00001 (= IDCODE), so there the tdo_oe monitor is what
    // detects a missed TLR. 6.1.1.1 a, b; 6.1.1.2
    task automatic s5_tms_reset_all_states();
        logic [4:0]  k;
        logic [3:0]  t;
        logic [31:0] seq;
        int          len;
        sc_begin("S5 TMS=1 x5 -> Test-Logic-Reset from all 16 states");
        for (k = 5'd0; k < 5'd16; k = k + 5'd1) begin
            t = k[3:0];
            reset_to_rti();
            load_ir(IR_BYPASS);
            nav_path(t, seq, len);
            tms_seq(seq, len);
            if (m_state !== t) fail($sformatf("TB navigation error: model in %s, wanted %s", sname(m_state), sname(t)));
            reset_tms();
            if (m_state !== S_TLR) fail("TB model not in Test-Logic-Reset after TMS=1 x5");
            tms_seq(32'b00, 2);   // Run-Test/Idle, Run-Test/Idle
            check_idcode($sformatf("S5 from %s: TMS=1 x5 then IDCODE", sname(t)));
        end
        sc_end();
    endtask

    // S6: TRST* resets the TAP asynchronously (no TCK edge needed) and holds it in Test-Logic-Reset.
    // Release with TCK stopped (a: at 0, b: at 1) or with TCK running and TMS=1 (c) (decisions.md D-001).
    // (c) releases at a TCK rise in RTL and mid low phase in GLS (decisions.md D-006).
    // 4.6.1 a, e; 6.1.3.1 c; 6.1.2.1 a; 7.2.1 f; 4.5.1 a
    task automatic s6_trst_async();
        sc_begin("S6 TRST* asynchronous reset");

        // (a) TCK stopped at 0
        reset_to_rti();
        load_ir(IR_BYPASS);
        tms_seq(32'b100, 3);                    // Shift-DR
        repeat (3) tick(1'b0, 1'b0);
        check_bit("S6a tdo_oe active in Shift-DR before TRST*", oe_obs, 1'b1);
        #(37.0);                                // not aligned to any TCK edge
        drive_trst_n(1'b0);
        #(TDO_DLY_MAX + 1.0);
        check_bit("S6a tdo_oe drops on TRST* fall with TCK stopped at 0", oe_obs, 1'b0);
        // TMS 0,1,0,0,0 would reach Shift-DR from Test-Logic-Reset if TRST* were ignored.
        tick(1'b0, 1'b1); tick(1'b1, 1'b1); tick(1'b0, 1'b1); tick(1'b0, 1'b1); tick(1'b0, 1'b1);
        check_bit("S6a tdo_oe stays inactive while TRST* is low and TCK runs", last_oe_post, 1'b0);
        tms = 1'b1;
        #(20.0);
        drive_trst_n(1'b1);                     // TCK stopped, TMS = 1
        #(20.0);
        tick(1'b0, 1'b1);                       // Test-Logic-Reset -> Run-Test/Idle
        check_idcode("S6a IR = IDCODE after TRST* (7.2.1 f)");

        // (b) TCK stopped at 1
        reset_to_rti();
        load_ir(IR_BYPASS);
        tms_seq(32'b100, 3);
        repeat (2) tick(1'b0, 1'b0);
        tms = 1'b0;
        tdi = 1'b0;
        #(T_HALF - T_DRV);
        drive_tck(1'b1);                        // rising edge in Shift-DR, then TCK held at 1
        #(T_HALF / 2.0 + 3.0);
        check_bit("S6b tdo_oe active with TCK stopped at 1", oe_obs, 1'b1);
        drive_trst_n(1'b0);
        #(TDO_DLY_MAX + 1.0);
        check_bit("S6b tdo_oe drops on TRST* fall with TCK stopped at 1", oe_obs, 1'b0);
        #(T_HALF);
        tms = 1'b1;
        #(10.0);
        drive_trst_n(1'b1);
        #(10.0);
        drive_tck(1'b0);
        #(T_DRV);
        tick(1'b0, 1'b1);
        check_idcode("S6b IR = IDCODE after TRST* with TCK stopped at 1");

        // (c) TCK running with TMS = 1
        reset_to_rti();
        load_ir(IR_BYPASS);
        tms_seq(32'b100, 3);
        tick(1'b0, 1'b0);
        drive_trst_n(1'b0);
        repeat (2) tick(1'b1, 1'b1);
        tms = 1'b1;
        tdi = 1'b1;
`ifdef GLS
        // Gate level: release in the middle of the low phase (30 ns after TCK fall, 20 ns before the
        // next rise). A release in the same time step as the rise is a recovery/removal violation by
        // construction, and the cell models turn it into X through their notifiers, which cannot
        // express D-001's "either outcome is Test-Logic-Reset" argument (decisions.md D-006).
        #((T_HALF - T_DRV) / 2.0);
        drive_trst_n(1'b1);
        #((T_HALF - T_DRV) / 2.0);
        drive_tck(1'b1);
`else
        // RTL: release in the same time step as a rising edge (D-001: with TMS = 1 the result is
        // Test-Logic-Reset whether or not that edge is seen).
        #(T_HALF - T_DRV);
        drive_trst_n(1'b1);
        drive_tck(1'b1);
`endif
        #(T_HALF);
        drive_tck(1'b0);
        #(T_DRV);
        tick(1'b1, 1'b1);
        tick(1'b0, 1'b1);
        check_idcode("S6c IR = IDCODE after TRST* released while TCK runs with TMS=1");

        sc_end();
    endtask

    // S7: data scans may be split through Pause/Exit2 without losing or duplicating bits.
    // Non-shift edges carry TDI = 1, data edges TDI = 0, so a stray shift corrupts the result.
    // Fig. 6-1; Table 6-2; Table 7-1; 4.4.1 c
    task automatic s7_pause_continuity();
        logic [7:0] d8;
        sc_begin("S7 Pause/Exit2 continuity");

        // DR: 32-bit IDCODE as 10 + 22 bits around Pause-DR
        reset_to_rti();                         // IR = IDCODE
        tms_seq(32'b100, 3);                    // Shift-DR
        acc_clear();
        for (int i = 0; i < 10; i++) begin tick(i == 9, 1'b0); acc_push(); end   // ... Exit1-DR
        tick(1'b0, 1'b1);                       // Pause-DR
        repeat (3) tick(1'b0, 1'b1);            // stay in Pause-DR
        tick(1'b1, 1'b1);                       // Exit2-DR
        tick(1'b0, 1'b1);                       // Shift-DR (no shift on this edge)
        for (int i = 0; i < 22; i++) begin tick(i == 21, 1'b0); acc_push(); end  // ... Exit1-DR
        tms_seq(32'b10, 2);                     // Update-DR, Run-Test/Idle
        check_bits("S7 DR: 10 + 22 bits across Pause-DR = IDCODE", acc >> (MAXB - 32), `ZX(32, IDCODE_EXP), 32);

        // DR, BYPASS: 4 + 4 bits around Pause-DR. Pause/Exit2 do not pass Capture-DR, so the bit
        // shifted in on the Shift-DR -> Exit1-DR edge must come out first after resuming; the result
        // equals one continuous 8-bit BYPASS scan (10.1.1 b, 4.4.1 c). TDI bit 2 != bit 3 on purpose.
        load_ir(IR_BYPASS);
        tms_seq(32'b100, 3);                    // Shift-DR
        acc_clear();
        d8 = BYP_SPLIT_DIN;
        for (int i = 0; i < 4; i++) begin tick(i == 3, d8[0]); acc_push(); d8 = d8 >> 1; end  // ... Exit1-DR
        tick(1'b0, 1'b1);                       // Pause-DR
        tick(1'b1, 1'b1);                       // Exit2-DR
        tick(1'b0, 1'b1);                       // Shift-DR (no shift on this edge)
        for (int i = 0; i < 4; i++) begin tick(i == 3, d8[0]); acc_push(); d8 = d8 >> 1; end  // ... Exit1-DR
        tms_seq(32'b10, 2);
        check_bits("S7 BYPASS: 4 + 4 bits across Pause-DR = continuous 8-bit BYPASS scan", acc >> (MAXB - 8),
                   `ZX(8, {BYP_SPLIT_DIN[6:0], 1'b0}), 8);

        // IR: TDI 1,0 | 0,0,0 around Pause-IR loads 00001 (IDCODE) over BYPASS
        load_ir(IR_BYPASS);
        tms_seq(32'b1100, 4);                   // Shift-IR
        acc_clear();
        tick(1'b0, 1'b1); acc_push();
        tick(1'b1, 1'b0); acc_push();           // Exit1-IR
        tick(1'b0, 1'b1);                       // Pause-IR
        tick(1'b0, 1'b1);                       // stay in Pause-IR
        tick(1'b1, 1'b1);                       // Exit2-IR
        tick(1'b0, 1'b1);                       // Shift-IR (no shift on this edge)
        tick(1'b0, 1'b0); acc_push();
        tick(1'b0, 1'b0); acc_push();
        tick(1'b1, 1'b0); acc_push();           // Exit1-IR
        tms_seq(32'b10, 2);                     // Update-IR, Run-Test/Idle
        check_bits("S7 IR: 2 + 3 bits across Pause-IR shift out 00001", acc >> (MAXB - 5), `ZX(5, IR_CAPTURE_EXP), 5);
        check_idcode("S7 IR: 1,0,0,0,0 shifted across Pause-IR selects IDCODE");

        sc_end();
    endtask

    // S8: tdo_oe is active from the first falling edge in Shift-xR to the first falling edge after
    // leaving it. 6.1.2.1 c, d + NOTE 2; Table 6-2; 4.5.1 b
    task automatic tick_oe(input logic tms_v, input logic exp_hi, input logic exp_post, input string what);
        tick(tms_v, 1'b1);
        check_bit($sformatf("S8 %s: tdo_oe while TCK high", what), last_oe_hi, exp_hi);
        check_bit($sformatf("S8 %s: tdo_oe after TCK fall", what), last_oe_post, exp_post);
    endtask

    task automatic s8_oe_window();
        sc_begin("S8 tdo_oe window");
        reset_to_rti();
        load_ir(IR_BYPASS);
        // DR side                                   high post
        tick_oe(1'b1, 1'b0, 1'b0, "-> Select-DR-Scan");
        tick_oe(1'b0, 1'b0, 1'b0, "-> Capture-DR");
        tick_oe(1'b0, 1'b0, 1'b1, "-> Shift-DR (enable at first fall)");
        tick_oe(1'b0, 1'b1, 1'b1, "Shift-DR");
        tick_oe(1'b1, 1'b1, 1'b0, "-> Exit1-DR (disable at first fall after leaving)");
        tick_oe(1'b0, 1'b0, 1'b0, "-> Pause-DR");
        tick_oe(1'b1, 1'b0, 1'b0, "-> Exit2-DR");
        tick_oe(1'b0, 1'b0, 1'b1, "Exit2-DR -> Shift-DR");
        tick_oe(1'b1, 1'b1, 1'b0, "Shift-DR -> Exit1-DR");
        tick_oe(1'b1, 1'b0, 1'b0, "-> Update-DR");
        tick_oe(1'b0, 1'b0, 1'b0, "-> Run-Test/Idle");
        // IR side (shifts 1,1,1,1,1 -> IR stays BYPASS)
        tick_oe(1'b1, 1'b0, 1'b0, "-> Select-DR-Scan");
        tick_oe(1'b1, 1'b0, 1'b0, "-> Select-IR-Scan");
        tick_oe(1'b0, 1'b0, 1'b0, "-> Capture-IR");
        tick_oe(1'b0, 1'b0, 1'b1, "-> Shift-IR (enable at first fall)");
        repeat (4) tick_oe(1'b0, 1'b1, 1'b1, "Shift-IR");
        tick_oe(1'b1, 1'b1, 1'b0, "-> Exit1-IR (disable at first fall after leaving)");
        tick_oe(1'b1, 1'b0, 1'b0, "-> Update-IR");
        tick_oe(1'b0, 1'b0, 1'b0, "-> Run-Test/Idle");
        check_bypass("S8 IR still BYPASS");
        sc_end();
    endtask

    // S9: TDO changes only on TCK falling edges (edge checker), and nothing changes while TCK is
    // stopped at 0 even if TMS/TDI toggle. 4.5.1 a; 6.1.2.1 d; 4.2.1 a; 10.1.1 b
    task automatic s9_tdo_falling_edge_only();
        logic [15:0] d;
        logic        tdo_before, oe_before;
        sc_begin("S9 TDO changes only on TCK falling edge");
        reset_to_rti();
        load_ir(IR_BYPASS);
        tms_seq(32'b100, 3);                    // Shift-DR
        acc_clear();
        d = 16'h5555;                           // TDI toggles every cycle (1,0,1,0,...)
        for (int i = 0; i < 8; i++) begin tick(1'b0, d[0]); acc_push(); d = d >> 1; end
        tdo_before = tdo_obs;
        oe_before  = oe_obs;
        repeat (10) begin                       // TCK stopped at 0 for 10 us
            #(500.0);
            tms = ~tms;
            tdi = ~tdi;
            #(500.0);
        end
        check_bit("S9 tdo unchanged while TCK stopped at 0", tdo_obs, tdo_before);
        check_bit("S9 tdo_oe unchanged while TCK stopped at 0", oe_obs, oe_before);
        for (int i = 0; i < 8; i++) begin tick(i == 7, d[0]); acc_push(); d = d >> 1; end   // ... Exit1-DR
        tms_seq(32'b10, 2);
        check_bits("S9 16-bit BYPASS scan with a 10 us TCK stop: 0, then TDI delayed one bit",
                   acc >> (MAXB - 16), `ZX(16, {15'h5555, 1'b0}), 16);
        sc_end();
    endtask

    // S10: 3-TAP chain. IR length and device count as a board-level host would find them, then a
    // blind IDCODE read after Test-Logic-Reset. 7.1.1 d, 7.1.2; 8.4.1 c; 10.1.1 b; 8.13.2; 12.1.2; 4.4.1 c
    task automatic s10_chain();
        bits_t dout, tmp;
        int    irlen, ndev;
        sc_begin("S10 3-TAP chain");
        sel_chain = 1'b1;
        reset_to_rti();

        // (a) IR scan of 40 ones: three capture patterns, then the TDI ones
        shift_ir({MAXB{1'b1}}, 40, dout);
        check_bits("S10a IR scan: 3 x 00001 then TDI ones", dout, {{(MAXB-15){1'b1}}, 15'b00001_00001_00001}, 40);
        irlen = 0;
        tmp   = dout;
        for (int i = 0; i < 40; i++) begin
            if (tmp[0] == 1'b0) irlen = i + 1;
            tmp = tmp >> 1;
        end
        $display("  chain IR length (bits before the TDI ones) = %0d", irlen);
        if (irlen != 3 * IR_LEN) fail($sformatf("S10a total IR length %0d, expected %0d", irlen, 3 * IR_LEN));

        // (b) all three in BYPASS: a single 1 on TDI appears after 3 cycles
        shift_dr(`ZX(8, 8'b0000_0001), 8, dout);
        check_bits("S10b BYPASS x3: captured 0,0,0 then TDI", dout, `ZX(8, 8'b0000_1000), 8);
        ndev = -1;
        tmp  = dout;
        for (int i = 0; i < 8; i++) begin
            if (tmp[0] == 1'b1 && ndev < 0) ndev = i;
            tmp = tmp >> 1;
        end
        $display("  chain device count (bypass delay) = %0d", ndev);
        if (ndev != 3) fail($sformatf("S10b device count %0d, expected 3", ndev));

        // (c) blind interrogation: TLR selects IDCODE in all three
        reset_tms();
        tick(1'b0, 1'b1);
        shift_dr(`ZX(1, 1'b1), 97, dout);
        check_bits("S10c DR scan after TMS reset: 3 x IDCODE then TDI", dout,
                   `ZX(97, {1'b1, IDCODE_EXP, IDCODE_EXP, IDCODE_EXP}), 97);

        sel_chain = 1'b0;
        sc_end();
    endtask

    // ------------------------------------------------------------------ main
    initial begin
        logic [5:0] k;
        int         n_arcs;

        $timeformat(-9, 1, " ns", 0);
        #(1.0);
        chk_en = 1'b1;

        s1_idcode_after_reset();
        s2_capture_ir();
        s3_bypass();
        s4_unassigned_ir();
        s5_tms_reset_all_states();
        s6_trst_async();
        s7_pause_continuity();
        s8_oe_window();
        s9_tdo_falling_edge_only();
        s10_chain();

        n_arcs = 0;
        for (k = 6'd0; k < 6'd32; k = k + 6'd1) begin
            if (arc_hit[k[4:0]] === 1'b1) n_arcs++;
            else $display("  arc not covered: %s with TMS=%b", sname(k[4:1]), k[0]);
        end
        $display("monitors: tdo_oe mismatches %0d, TDO edge violations %0d", err_oe, err_edge);
        $display("TAP arc coverage: %0d/32", n_arcs);
        if (n_arcs != 32) fail("TAP arc coverage incomplete");

        if (total_errors() == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("%0d FAILURES", total_errors());
            $fatal(1);
        end
        $finish;
    end

    initial begin
        #(TIMEOUT);
        $display("TIMEOUT");
        $fatal(1, "watchdog timeout");
    end

endmodule
