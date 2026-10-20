// rtl/jtag_tap.v — IEEE 1149.1-2013 TAP controller: 16-state FSM, 5-bit IR, BYPASS, IDCODE.
//
// Single clock domain (TCK). trst_n is an asynchronous reset applied directly to every flop, with no
// release synchronizer (decisions.md D-001). Release is assumed with TCK stopped or TMS = 1
// (4.6.1 e). In Test-Logic-Reset with TMS = 1, every flop's next value equals its reset value.
//
// Clock edges (CLAUDE.md §2):
//   posedge tck : FSM state, IR shift stage, bypass register, device ID register
//   negedge tck : IR parallel output (7.2.1 d, e), TDO output flop and its enable (6.1.2.1 d)
//
// Opcodes: 5'h01 = IDCODE (reset value). Every other code, including 5'h1F (8.4.1 b) and 5'h00
// (8.4.1 g), selects BYPASS (8.1.1 d).

module jtag_tap #(
    parameter [31:0] IDCODE_VALUE = 32'hDEADBEEF  // 12.1.1 d, Fig. 12-1: [0] = 1; [11:1] != 11'h07F (12.2.1 b)
) (
    input  wire tck,      // 4.2
    input  wire tms,      // 4.3.1 a: sampled on TCK rise
    input  wire tdi,      // 4.4.1 a: sampled on TCK rise
    input  wire trst_n,   // 4.6.1 a, 6.1.3.1 c: asynchronous reset to Test-Logic-Reset
    output wire tdo,      // 4.5.1 a, 6.1.2.1 d: changes on TCK fall only
    output wire tdo_oe    // 4.5.1 b, Table 6-2 + NOTE 2: active half a cycle behind Shift-IR/DR
);

    // ------------------------------------------------------------------ constants
    localparam             IR_LEN     = 5;         // 7.1.1 a (>= 2), RISC-V Debug §6.1
    localparam [IR_LEN-1:0] IR_CAPTURE = 5'b00001; // 7.1.1 d (two LSBs "01"), 7.1.1 e (others fixed 0)
    localparam [IR_LEN-1:0] IR_IDCODE  = 5'h01;    // 8.13.1 f, RISC-V Debug §6.1
    localparam             ID_LEN     = 32;        // 12.1.1 d

    // TAP controller states (6.1.1.1 a, Fig. 6-1)
    localparam [3:0] TEST_LOGIC_RESET = 4'd0,
                     RUN_TEST_IDLE    = 4'd1,
                     SELECT_DR_SCAN   = 4'd2,
                     CAPTURE_DR       = 4'd3,
                     SHIFT_DR         = 4'd4,
                     EXIT1_DR         = 4'd5,
                     PAUSE_DR         = 4'd6,
                     EXIT2_DR         = 4'd7,
                     UPDATE_DR        = 4'd8,
                     SELECT_IR_SCAN   = 4'd9,
                     CAPTURE_IR       = 4'd10,
                     SHIFT_IR         = 4'd11,
                     EXIT1_IR         = 4'd12,
                     PAUSE_IR         = 4'd13,
                     EXIT2_IR         = 4'd14,
                     UPDATE_IR        = 4'd15;

    // ------------------------------------------------------------------ registers
    reg [3:0]        tck_state_q,     tck_state_d;
    reg [IR_LEN-1:0] tck_ir_sr_q,     tck_ir_sr_d;      // IR shift-register stage
    reg [IR_LEN-1:0] tck_ir_q,        tck_ir_d;         // IR parallel output (current instruction)
    reg              tck_bypass_q,    tck_bypass_d;     // bypass register (10.1.1 a)
    reg [ID_LEN-1:0] tck_idcode_sr_q, tck_idcode_sr_d;  // device ID register (12.1.1 a)
    reg              tck_tdo_q,       tck_tdo_d;
    reg              tck_tdo_oe_q,    tck_tdo_oe_d;

    // ------------------------------------------------------------------ FSM (6.1.1.1 b: TMS at TCK rise)
    always @* begin
        case (tck_state_q)
            TEST_LOGIC_RESET: tck_state_d = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    tck_state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   tck_state_d = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       tck_state_d = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         tck_state_d = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         tck_state_d = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         tck_state_d = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         tck_state_d = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        tck_state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   tck_state_d = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       tck_state_d = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         tck_state_d = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         tck_state_d = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         tck_state_d = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         tck_state_d = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        tck_state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          tck_state_d = TEST_LOGIC_RESET;
        endcase
    end

    wire tck_tlr        = (tck_state_q == TEST_LOGIC_RESET);
    wire tck_capture_ir = (tck_state_q == CAPTURE_IR);
    wire tck_shift_ir   = (tck_state_q == SHIFT_IR);
    wire tck_update_ir  = (tck_state_q == UPDATE_IR);
    wire tck_capture_dr = (tck_state_q == CAPTURE_DR);
    wire tck_shift_dr   = (tck_state_q == SHIFT_DR);

    // Instruction decode: IDCODE selects only the ID register (8.13.1 b); all other codes select
    // the bypass register (8.4.1 c, 8.1.1 d). Exactly one serial path per instruction (8.1.1 c).
    wire tck_sel_idcode = (tck_ir_q == IR_IDCODE);
    wire tck_dr_so      = tck_sel_idcode ? tck_idcode_sr_q[0] : tck_bypass_q;

    // ------------------------------------------------------------------ next values
    always @* begin
        // IR shift stage (Table 7-1; 7.2.1 c: operations on TCK rise)
        tck_ir_sr_d = tck_ir_sr_q;
        if (tck_capture_ir)
            tck_ir_sr_d = IR_CAPTURE;                                   // 7.1.1 d, e
        else if (tck_shift_ir)
            tck_ir_sr_d = {tdi, tck_ir_sr_q[IR_LEN-1:1]};               // toward TDO, no inversion (7.1.1 c)

        // IR parallel output, latched on TCK fall
        tck_ir_d = tck_ir_q;
        if (tck_tlr)
            tck_ir_d = IR_IDCODE;                                       // 7.2.1 e
        else if (tck_update_ir)
            tck_ir_d = tck_ir_sr_q;                                     // 7.2.1 d

        // Bypass register: only while selected (8.1.1 b)
        tck_bypass_d = tck_bypass_q;
        if (!tck_sel_idcode && tck_capture_dr)
            tck_bypass_d = 1'b0;                                        // 10.1.1 b
        else if (!tck_sel_idcode && tck_shift_dr)
            tck_bypass_d = tdi;

        // Device ID register: only while selected
        tck_idcode_sr_d = tck_idcode_sr_q;
        if (tck_sel_idcode && tck_capture_dr)
            tck_idcode_sr_d = IDCODE_VALUE;                             // 8.13.1 c, 12.1.1 c
        else if (tck_sel_idcode && tck_shift_dr)
            tck_idcode_sr_d = {tdi, tck_idcode_sr_q[ID_LEN-1:1]};

        // TDO source (Table 6-2); value outside Shift-xR is undefined, so it is held
        tck_tdo_d = tck_tdo_q;
        if (tck_shift_ir)
            tck_tdo_d = tck_ir_sr_q[0];
        else if (tck_shift_dr)
            tck_tdo_d = tck_dr_so;

        // TDO driver enable (Table 6-2 + NOTE 2)
        tck_tdo_oe_d = tck_shift_ir | tck_shift_dr;
    end

    // ------------------------------------------------------------------ TCK rise
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tck_state_q     <= TEST_LOGIC_RESET;                        // 4.6.1 a
            tck_ir_sr_q     <= IR_CAPTURE;
            tck_bypass_q    <= 1'b0;
            tck_idcode_sr_q <= IDCODE_VALUE;
        end else begin
            tck_state_q     <= tck_state_d;
            tck_ir_sr_q     <= tck_ir_sr_d;
            tck_bypass_q    <= tck_bypass_d;
            tck_idcode_sr_q <= tck_idcode_sr_d;
        end
    end

    // ------------------------------------------------------------------ TCK fall
    always @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tck_ir_q     <= IR_IDCODE;                                  // 7.2.1 f
            tck_tdo_q    <= 1'b0;
            tck_tdo_oe_q <= 1'b0;
        end else begin
            tck_ir_q     <= tck_ir_d;
            tck_tdo_q    <= tck_tdo_d;
            tck_tdo_oe_q <= tck_tdo_oe_d;
        end
    end

    assign tdo    = tck_tdo_q;
    assign tdo_oe = tck_tdo_oe_q;

endmodule
