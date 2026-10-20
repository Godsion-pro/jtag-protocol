// sim/main_tap.cpp — Stage 1: Verilated jtag_tap (model class Vrbb_tap) behind the remote_bitbang server.
// Usage: ./sim/obj_dir/Vrbb_tap [+port=9999]

#include "Vrbb_tap.h"
#include "rbb_server.h"
#include "verilated.h"

#include <cstdlib>
#include <cstring>
#include <memory>

namespace {

class TapTarget : public RbbTarget {
  public:
    explicit TapTarget(Vrbb_tap& top) : top_(top) {}

    void set_jtag(bool tck, bool tms, bool tdi) override {
        top_.tck = tck;
        top_.tms = tms;
        top_.tdi = tdi;
        top_.eval();
    }

    // No SRST in this design (CLAUDE.md §0); TRST* is active low.
    void set_reset(bool trst_asserted, bool /*srst_asserted*/) override {
        top_.trst_n = !trst_asserted;
        top_.eval();
    }

    // While the TDO driver is inactive (4.5.1 b) the pin floats; model a board pull-up.
    bool get_tdo() override { return top_.tdo_oe ? (top_.tdo != 0) : true; }

  private:
    Vrbb_tap& top_;
};

int parse_port(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
        if (std::strncmp(argv[i], "+port=", 6) == 0) return std::atoi(argv[i] + 6);
    }
    return 9999;
}

}  // namespace

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);
    const std::unique_ptr<Vrbb_tap> top{new Vrbb_tap{ctx.get(), "jtag_tap"}};

    // Power-up: no POR in the design, so TRST* starts asserted (6.1.3.1 a), then is released with
    // TCK stopped at 0 and TMS = 1 (4.6.1 e, decisions.md D-001).
    top->tck    = 0;
    top->tms    = 1;
    top->tdi    = 1;
    top->trst_n = 0;
    top->eval();
    top->trst_n = 1;
    top->eval();

    TapTarget target{*top};
    RbbServer server{parse_port(argc, argv), target};
    const int rc = server.run();

    top->final();
    return rc;
}
