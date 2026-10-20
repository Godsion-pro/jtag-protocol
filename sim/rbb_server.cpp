// sim/rbb_server.cpp — OpenOCD remote_bitbang server. Protocol summary in rbb_server.h.

#include "rbb_server.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <string>

namespace {

bool send_all(int fd, const std::string& buf) {
    size_t done = 0;
    while (done < buf.size()) {
        const ssize_t n = send(fd, buf.data() + done, buf.size() - done, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            std::perror("rbb: send");
            return false;
        }
        done += static_cast<size_t>(n);
    }
    return true;
}

}  // namespace

RbbServer::RbbServer(int port, RbbTarget& target) : port_(port), target_(target) {}

int RbbServer::run() {
    const int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        std::perror("rbb: socket");
        return 1;
    }
    const int one = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);  // local OpenOCD only
    addr.sin_port        = htons(static_cast<uint16_t>(port_));
    if (bind(listen_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::perror("rbb: bind");
        close(listen_fd);
        return 1;
    }
    if (listen(listen_fd, 1) < 0) {
        std::perror("rbb: listen");
        close(listen_fd);
        return 1;
    }
    std::printf("rbb: listening on 127.0.0.1:%d\n", port_);
    std::fflush(stdout);

    const int fd = accept(listen_fd, nullptr, nullptr);
    close(listen_fd);
    if (fd < 0) {
        std::perror("rbb: accept");
        return 1;
    }
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    std::printf("rbb: client connected\n");
    std::fflush(stdout);

    const int rc = serve(fd);
    close(fd);
    std::printf("rbb: session end (writes %lu, reads %lu, resets %lu, unknown %lu)\n",
                n_write_, n_read_, n_reset_, n_unknown_);
    std::fflush(stdout);
    return rc;
}

int RbbServer::serve(int fd) {
    char        in[4096];
    std::string out;
    bool        quit = false;

    while (!quit) {
        const ssize_t n = recv(fd, in, sizeof(in), 0);
        if (n == 0) break;  // client closed the connection
        if (n < 0) {
            if (errno == EINTR) continue;
            std::perror("rbb: recv");
            return 1;
        }
        for (ssize_t i = 0; i < n && !quit; i++) {
            const char c = in[i];
            if (c >= '0' && c <= '7') {
                const int v = c - '0';
                target_.set_jtag((v & 0x4) != 0, (v & 0x2) != 0, (v & 0x1) != 0);
                n_write_++;
            } else if (c >= 'r' && c <= 'u') {
                const int v = c - 'r';
                target_.set_reset((v & 0x2) != 0, (v & 0x1) != 0);
                n_reset_++;
            } else if (c == 'R') {
                out.push_back(target_.get_tdo() ? '1' : '0');
                n_read_++;
            } else if (c == 'Q') {
                quit = true;
            } else if (c == 'B' || c == 'b' || c == '\n' || c == '\r') {
                // blink and line breaks: nothing to do
            } else {
                if (n_unknown_ < 10) std::fprintf(stderr, "rbb: unknown command 0x%02x\n", c & 0xff);
                n_unknown_++;
            }
        }
        // Answer every read of this chunk before blocking on the next one.
        if (!out.empty()) {
            if (!send_all(fd, out)) return 1;
            out.clear();
        }
    }
    return 0;
}
