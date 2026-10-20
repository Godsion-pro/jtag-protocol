// sim/rbb_server.h — OpenOCD remote_bitbang server (TCP, one client) in front of a simulated JTAG target.
//
// Protocol, checked against OpenOCD 0.12.0 doc/manual/jtag/drivers/remote_bitbang.txt and
// src/jtag/drivers/remote_bitbang.c:
//   '0'..'7'  write TCK, TMS, TDI = bits 2, 1, 0 of (c - '0')
//   'R'       read TDO; reply '0' or '1'
//   'r'..'u'  reset: bit 1 of (c - 'r') = TRST, bit 0 = SRST; 1 = asserted
//             (polarity as in src/jtag/drivers/sysfsgpio.c: trst=1 drives the active-low pin to 0)
//   'B', 'b'  blink on / off (ignored)
//   'Q'       quit
// Shared by all stages (main_tap.cpp now, main_riscv.cpp in stage 3).

#ifndef RBB_SERVER_H
#define RBB_SERVER_H

class RbbTarget {
  public:
    virtual ~RbbTarget() = default;
    virtual void set_jtag(bool tck, bool tms, bool tdi) = 0;
    virtual void set_reset(bool trst_asserted, bool srst_asserted) = 0;
    virtual bool get_tdo() = 0;
};

class RbbServer {
  public:
    RbbServer(int port, RbbTarget& target);

    // Listen on 127.0.0.1:port, accept one client, serve it until 'Q' or disconnect.
    // Returns 0 on a clean end of session, non-zero on a socket error.
    int run();

  private:
    int serve(int fd);

    int            port_;
    RbbTarget&     target_;
    unsigned long  n_write_   = 0;
    unsigned long  n_read_    = 0;
    unsigned long  n_reset_   = 0;
    unsigned long  n_unknown_ = 0;
};

#endif  // RBB_SERVER_H
