FROM ubuntu:16.04

MAINTAINER RockAndSka <yoann_mac_donald@hotmail.com>

# Versions to use
ENV GITLAB_RUNNER_VERSION=9.5.0 \
    DOCKER_ENGINE_VERSION=17.06.2 \
    DOCKER_MACHINE_VERSION=0.12.2 \
    DOCKER_COMPOSE_VERSION=1.16.1 \
    DIND_COMMIT=52379fa76dee07ca038624d639d9e14f4fb719ff \
    DUMB_VERSION=1.2.0

# Install components and do the preparations
# 1.   Install needed packages
# 2.   Install Dumb Init
# 3.   Install GitLab CI runner
# 4.   Install mesosdns-resolver
# 5.   Install Docker
# 6.   Install DinD hack
# 7.   Install Docker-Machine
# 8.   Install Docker-Compose
# 9.   Cleanup
# 10.  Add dockermap user (for DinD)
RUN apt-get update -qqy && \
    apt-get upgrade -qqy && \
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
    curl -sSL --fail -o /usr/bin/dumb-init  \
        "https://github.com/Yelp/dumb-init/releases/download/v${DUMB_VERSION}/dumb-init_1.2.0_amd64" && \
    chmod +x /usr/bin/dumb-init && \
    curl -ssL --fail -o /usr/local/bin/gitlab-ci-multi-runner \
        "https://gitlab-ci-multi-runner-downloads.s3.amazonaws.com/v${GITLAB_RUNNER_VERSION}/binaries/gitlab-ci-multi-runner-linux-amd64" && \
    ln -s /usr/local/bin/gitlab-ci-multi-runner /usr/local/bin/gitlab-runner && \
    chmod 0755 /usr/local/bin/gitlab-ci-multi-runner && \
    mkdir -p /etc/gitlab-runner/certs && \
    chmod -R 700 /etc/gitlab-runner && \
    curl -sSL --fail -o /usr/local/bin/mesosdns-resolver https://raw.githubusercontent.com/tobilg/mesosdns-resolver/master/mesosdns-resolver.sh && \
    chmod +x /usr/local/bin/mesosdns-resolver && \
    curl -sSL --fail -o - "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_ENGINE_VERSION}-ce.tgz" | tar xvz --transform 's#docker##' -C /usr/local/bin && \
    chmod 0755 /usr/local/bin/docker* && \
    curl -sSL --fail -o /usr/local/bin/dind https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind && \
    chmod a+x /usr/local/bin/dind && \
    curl -sSL --fail -o /usr/bin/docker-machine \
        "https://github.com/docker/machine/releases/download/v${DOCKER_MACHINE_VERSION}/docker-machine-Linux-x86_64" && \
    chmod 0755 /usr/bin/docker-machine && \
    curl -sSL --fail -o /usr/local/bin/docker-compose \
        "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" && \
    chmod 0755 /usr/local/bin/docker-compose && \
    apt-get autoremove -qyy && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    adduser --system --group dockremap && \
    echo 'dockremap:165536:65536' >> /etc/subuid && \
    echo 'dockremap:165536:65536' >> /etc/subgid

# Add wrapper script
ADD register_and_run.sh /

# Expose volumes
VOLUME ["/var/lib/docker", "/etc/gitlab-runner", "/home/gitlab-runner"]

ENTRYPOINT ["/usr/bin/dumb-init", "/register_and_run.sh"]
