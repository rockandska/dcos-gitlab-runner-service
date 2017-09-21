FROM ubuntu:16.04

MAINTAINER RockAndSka <yoann_mac_donald@hotmail.com>

# Versions to use
ENV GITLAB_RUNNER_VERSION=9.5.0 \
    DOCKER_ENGINE_VERSION=17.06.2 \
    DOCKER_MACHINE_VERSION=0.12.2 \
    DOCKER_COMPOSE_VERSION=1.16.1 \
    DIND_COMMIT=52379fa76dee07ca038624d639d9e14f4fb719ff \
    DUMB_VERSION=1.2.0

# Install needed packages
RUN apt-get update -qqy && \
    apt-get install --no-install-recommends -qqy \
        aufs-tools \
        btrfs-tools \
        bridge-utils \
        ca-certificates \
        curl \
        dnsutils \
        e2fsprogs \
        git \
        iptables \
        lsb-release \
        lxc \
        procps \
        ssh-client \
        software-properties-common \
        xz-utils && \
        apt-get autoremove -qyy && \
        rm -rf /var/lib/apt/lists/* && \
# Dumb-Init
    curl -SL --progress-bar --fail -o /usr/bin/dumb-init  \
        "https://github.com/Yelp/dumb-init/releases/download/v${DUMB_VERSION}/dumb-init_1.2.0_amd64" && \
    chmod +x /usr/bin/dumb-init && \
# Gitlab CI Runner
    curl -SL --progress-bar --fail -o /usr/local/bin/gitlab-ci-multi-runner \
        "https://gitlab-ci-multi-runner-downloads.s3.amazonaws.com/v${GITLAB_RUNNER_VERSION}/binaries/gitlab-ci-multi-runner-linux-amd64" && \
    ln -s /usr/local/bin/gitlab-ci-multi-runner /usr/local/bin/gitlab-runner && \
    chmod 0755 /usr/local/bin/gitlab-ci-multi-runner && \
    mkdir -p /etc/gitlab-runner/certs && \
    chmod -R 700 /etc/gitlab-runner && \
# mesosdns-resolver
    curl -SL --progress-bar --fail -o /usr/local/bin/mesosdns-resolver https://raw.githubusercontent.com/tobilg/mesosdns-resolver/master/mesosdns-resolver.sh && \
    chmod +x /usr/local/bin/mesosdns-resolver && \
# Docker
    curl -SL --progress-bar --fail -o - "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_ENGINE_VERSION}-ce.tgz" | tar xvz --transform 's#docker##' -C /usr/local/bin && \
    chmod 0755 /usr/local/bin/docker* && \
# DinD Hack
    curl -SL --progress-bar --fail -o /usr/local/bin/dind https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind && \
    chmod a+x /usr/local/bin/dind && \
# Docker-Machine
    curl -SL --progress-bar --fail -o /usr/bin/docker-machine \
        "https://github.com/docker/machine/releases/download/v${DOCKER_MACHINE_VERSION}/docker-machine-Linux-x86_64" && \
    chmod 0755 /usr/bin/docker-machine && \
# Docker-Compose
    curl -SL --progress-bar --fail -o /usr/local/bin/docker-compose \
        "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-Linux-x86_64" && \
    chmod 0755 /usr/local/bin/docker-compose && \
# dockermap user (for DinD)
    adduser --system --group dockremap && \
    echo 'dockremap:165536:65536' >> /etc/subuid && \
    echo 'dockremap:165536:65536' >> /etc/subgid && \
# gitlab runner user
    adduser --disabled-login --gecos 'GitLab CI Runner' gitlab-runner && \
    addgroup docker && \
    usermod -a -G docker gitlab-runner

# Add wrapper script
ADD register_and_run.sh /

# Expose volumes
VOLUME ["/var/lib/docker", "/etc/gitlab-runner", "/home/gitlab-runner"]

ENTRYPOINT ["/usr/bin/dumb-init", "/register_and_run.sh"]
