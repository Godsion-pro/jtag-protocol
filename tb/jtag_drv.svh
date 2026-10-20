// tb/jtag_drv.svh — JTAG host driver tasks, `include'd inside a TB module (RTL/GLS shared).
//
// The including module must declare, before this include:
//   logic tck, tms, tdi, trst_n;      host-driven TAP inputs (driven only from the TB's main process)
//   wire  tdo_obs, oe_obs;            TDO / TDO enable of the TAP (or chain end) being observed
//   localparam real T_HALF, T_DRV, T_SMP;   half period, drive delay after TCK fall, sample lead before TCK rise
//   localparam int  MAXB;             width of bit vectors used by the shift tasks
// TCK and TRST* must only be changed through drive_tck / drive_trst_n so that the times of their
// falling edges are recorded before the edge happens (used by the TDO edge checker).
//
// Host timing (IEEE 1149.1-2013 6.1.2.1 NOTE 1, 4.3.2, 4.4.2): TMS/TDI change T_DRV after TCK falls,
// TDO is sampled T_SMP before TCK rises (TDO changes only on the falling edge, 4.5.1 a).
//
// Bit order conventions:
//   - Data vectors (din/dout of shift tasks): LSB first, bit 0 is the first bit on TDI / TDO.
//   - TMS sequences (tms_seq): time order reads left to right in the literal, i.e. bit [len-1] first.

typedef logic [MAXB-1:0] bits_t;

// Zero-extend a w-bit expression to bits_t.
`define ZX(w, x) {{(MAXB-(w)){1'b0}}, (x)}

realtime t_tck_fall  = -1.0e9;  // time of the latest TCK falling edge
realtime t_trst_fall = -1.0e9;  // time of the latest TRST* falling edge

logic last_tdo     = 1'b0;      // TDO sampled T_SMP before the latest rising edge
logic last_oe_hi   = 1'b0;      // tdo_oe sampled in the middle of the latest high phase
logic last_oe_post = 1'b0;      // tdo_oe sampled T_DRV after the latest falling edge

task automatic drive_tck(input logic v);
    if (!v) t_tck_fall = $realtime;
    tck = v;
endtask

task automatic drive_trst_n(input logic v);
    if (!v) t_trst_fall = $realtime;
    trst_n = v;
endtask

// One TCK cycle. Entry and exit: TCK = 0, T_DRV after a falling edge (or TCK stopped at 0).
task automatic tick(input logic tms_v, input logic tdi_v);
    tms = tms_v;
    tdi = tdi_v;
    #(T_HALF - T_DRV - T_SMP);
    last_tdo = tdo_obs;
    #(T_SMP);
    drive_tck(1'b1);
    #(T_HALF / 2.0);
    last_oe_hi = oe_obs;
    #(T_HALF / 2.0);
    drive_tck(1'b0);
    #(T_DRV);
    last_oe_post = oe_obs;
endtask

// Apply len TMS values (len <= 32), time order = seq[len-1] first. TDI held at 1 (4.4.1 b idle level).
task automatic tms_seq(input logic [31:0] seq, input int len);
    logic [31:0] s;
    s = seq << (32 - len);
    for (int i = 0; i < len; i++) begin
        tick(s[31], 1'b1);
        s = s << 1;
    end
endtask

// TMS = 1 for five rising edges reaches Test-Logic-Reset from any state (6.1.1.2).
task automatic reset_tms();
    repeat (5) tick(1'b1, 1'b1);
endtask

// TRST* pulse with TCK stopped at 0 and TMS held at 1 during release (4.6.1 a, e; decisions.md D-001).
task automatic trst_pulse();
    tms = 1'b1;
    #(T_HALF / 2.0);
    drive_trst_n(1'b0);
    #(T_HALF);
    drive_trst_n(1'b1);
    #(T_HALF / 2.0);
endtask

// Shift n bits (1 <= n <= MAXB) through the selected path, starting in a Shift state;
// the last bit is shifted with TMS = 1 (Shift -> Exit1). dout bit i = TDO before shift i.
task automatic shift_bits(input bits_t din, input int n, output bits_t dout);
    bits_t d;
    d    = din;
    dout = '0;
    for (int i = 0; i < n; i++) begin
        tick(i == n - 1, d[0]);
        dout = {last_tdo, dout[MAXB-1:1]};
        d    = d >> 1;
    end
    dout = dout >> (MAXB - n);
endtask

// IR scan from Run-Test/Idle back to Run-Test/Idle, n bits.
task automatic shift_ir(input bits_t din, input int n, output bits_t dout);
    tms_seq(32'b1100, 4);       // Select-DR, Select-IR, Capture-IR, Shift-IR
    shift_bits(din, n, dout);   // ... Exit1-IR
    tms_seq(32'b10, 2);         // Update-IR, Run-Test/Idle
endtask

// DR scan from Run-Test/Idle back to Run-Test/Idle, n bits.
task automatic shift_dr(input bits_t din, input int n, output bits_t dout);
    tms_seq(32'b100, 3);        // Select-DR, Capture-DR, Shift-DR
    shift_bits(din, n, dout);   // ... Exit1-DR
    tms_seq(32'b10, 2);         // Update-DR, Run-Test/Idle
endtask
