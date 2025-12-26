FROM ubuntu:22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      qemu-kvm qemu-utils iproute2 netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

COPY run-vjunos.sh /usr/local/bin/run-vjunos.sh
RUN chmod +x /usr/local/bin/run-vjunos.sh

CMD ["/usr/local/bin/run-vjunos.sh"]
