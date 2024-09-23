FROM ubuntu:22.04

ARG RUNNER_VERSION="2.319.1"
ENV RUNNER_VERSION=${RUNNER_VERSION}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update -y && apt upgrade -y && \
    apt install -y --no-install-recommends curl jq build-essential libssl-dev libffi-dev python3 python3-venv python3-dev python3-pip && \
    useradd -m docker

RUN curl -O -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" && \
tar xzf "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" && \
rm "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

RUN ./bin/installdependencies.sh && \
    chown -R docker /home/docker/actions-runner

COPY start.sh /home/docker/actions-runner/start.sh
RUN chmod +x start.sh

USER docker

ENTRYPOINT ["./start.sh"]