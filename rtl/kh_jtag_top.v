// rtl/kh_jtag_top.v — synthesis top.
// Stage 1: TAP only. Stage 2 adds the boundary-scan register, stage 3 the JTAG-DTM and debug module.
// Hierarchy below this module is kept in synthesis so per-module area can be reported (CLAUDE.md §2).

module kh_jtag_top (
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    input  wire trst_n,
    output wire tdo,
    output wire tdo_oe
);

    jtag_tap u_jtag_tap (
        .tck    (tck),
        .tms    (tms),
        .tdi    (tdi),
        .trst_n (trst_n),
        .tdo    (tdo),
        .tdo_oe (tdo_oe)
    );

endmodule
