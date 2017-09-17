#!/bin/sh
set -eu

# Trap SIGTERM
trap 'trap - TERM INT EXIT;_getTerminationSignal' TERM INT EXIT

# Set data directory
DATA_DIR="/etc/gitlab-runner"

# Set config file
CONFIG_FILE=${CONFIG_FILE:-$DATA_DIR/config.toml}

# Set custom certificate authority paths
CA_CERTIFICATES_PATH=${CA_CERTIFICATES_PATH:-$DATA_DIR/certs/ca.crt}
LOCAL_CA_PATH="/usr/local/share/ca-certificates/ca.crt"

# Derive the RUNNER_NAME from the MESOS_TASK_ID if not set,and if MESOS_TASK_ID is not set then Rancher
export RUNNER_NAME=${RUNNER_NAME:=${MESOS_TASK_ID:=$(curl -s rancher-metadata/latest/self/container/name 2> /dev/null || :)}}

# Enable non-interactive registration the the main GitLab instance
export REGISTER_NON_INTERACTIVE=true

# Set RUNNER_DIR
RUNNER_DIR=${MESOS_SANDBOX:=/home/gitlab-runner}

# Set the RUNNER_BUILDS_DIR
RUNNER_BUILDS_DIR=${RUNNER_DIR}/builds

# Set the RUNNER_CACHE_DIR
RUNNER_CACHE_DIR=${RUNNER_DIR}/cache

# Set the RUNNER_WORK_DIR
RUNNER_WORK_DIR=${RUNNER_DIR}/work

# Set the RUNNER_DATA_DIR ( used to .ssh and .docker persistence )
RUNNER_DATA_DIR=${RUNNER_DIR}/data

# Create update_ca function
update_ca() {
  echo "==> Updating CA certificates..."
  cp "${CA_CERTIFICATES_PATH}" "${LOCAL_CA_PATH}"
  update-ca-certificates --fresh > /dev/null
}

# Termination function
_getTerminationSignal() {
    echo "Caught SIGTERM signal! Deleting GitLab Runner!"
    # Unregister (by name). See https://gitlab.com/gitlab-org/gitlab-ci-multi-runner/tree/master/docs/commands#by-name
    gitlab-runner unregister --name ${RUNNER_NAME}
    # Exit with error code 0
    exit 0
}

# Ensure that either GITLAB_SERVICE_NAME or CI_SERVER_URL is set. Otherwise we can't register!
if [ -z ${GITLAB_SERVICE_NAME+x} ]; then
    # Check that
    if [ -z ${CI_SERVER_URL+x} ]; then
        echo "==> Need to either set GITLAB_SERVICE_NAME to the service name of GitLab (e.g. gitlab.marathon.mesos), or CI_SERVER_URL to the URL of the GitLab instance! Exiting..."
        exit 1
    fi
fi

# Ensure REGISTRATION_TOKEN
if [ -z ${REGISTRATION_TOKEN+x} ]; then
    echo "==> Need to set REGISTRATION_TOKEN. You can get this token in GitLab -> Admin Area -> Overview -> Runners. Exiting..."
    exit 1
fi

# Ensure RUNNER_EXECUTOR
if [ -z ${RUNNER_EXECUTOR+x} ]; then
    echo "==> Need to set RUNNER_EXECUTOR. Please choose a valid executor, like 'shell' or 'docker' etc. Exiting..."
    exit 1
fi

# Check for RUNNER_CONCURRENT_BUILDS variable (custom defined variable)
if [ -z ${RUNNER_CONCURRENT_BUILDS+x} ]; then
    echo "==> Concurrency is set to 1"
    echo "concurrent = 1" > ${CONFIG_FILE}
else
    echo "==> Concurrency is set to ${RUNNER_CONCURRENT_BUILDS}"
    echo "concurrent = ${RUNNER_CONCURRENT_BUILDS}" > ${CONFIG_FILE}
fi

# Check for RUNNER_CHECK_INTERVAL variable (custom defined variable)
if [ -z ${RUNNER_CHECK_INTERVAL+x} ]; then
    echo "==> Check interval is set to 0"
    echo "check_interval = 0" >> ${CONFIG_FILE}
else
    echo "==> Check interval is set to ${RUNNER_CHECK_INTERVAL}"
    echo "check_interval = ${RUNNER_CHECK_INTERVAL}" >> ${CONFIG_FILE}
fi

# Compare the custom CA path to the current CA path
if [ -f "${CA_CERTIFICATES_PATH}" ]; then
  # Update the CA if the custom CA is different than the current
  cmp --silent "${CA_CERTIFICATES_PATH}" "${LOCAL_CA_PATH}" || update_ca
fi

# Check whether CI_SERVER_URL is non-empty. If so, use the CI_SERVER_URL directly, if not, use
if [ -z ${CI_SERVER_URL+x} ]; then
    # Display the GitLab instance URL discovery method
    echo "==> Using Mesos DNS to discover the GitLab instance URL"

    # Derive the Mesos DNS server ip address by getting the first nameserver entry from /etc/resolv.conf which is a workaround
    export MESOS_DNS_SERVER=$(cat /etc/resolv.conf | grep nameserver | awk -F" " '{print $2}' | head -n 1)

    # Set the CI_SERVER_URL by resolving the Mesos DNS service name endpoint.
    # Environment variable GITLAB_SERVICE_NAME must be defined in the Marathon app.json
    export CI_SERVER_URL=http://$(mesosdns-resolver --serviceName $GITLAB_SERVICE_NAME --server $MESOS_DNS_SERVER --portIndex 0)
    
    if [ -z ${CI_SERVER_URL+x} ];then
        echo "Failed to retrieve CI_SERVER_URL by Mesos" 1>&2
        exit 1
    fi
else
    # Display the GitLab instance URL discovery method
    echo "==> Using the CI_SERVER_URL environment variable to set the GitLab instance URL"
fi

# Create directories
mkdir -p $RUNNER_BUILDS_DIR $RUNNER_CACHE_DIR $RUNNER_WORK_DIR $RUNNER_DATA_DIR ${RUNNER_DATA_DIR}/.ssh ${RUNNER_DATA_DIR}/.docker

# Generate deploy key
if [ ! -e ${RUNNER_DATA_DIR}/.ssh/id_rsa -o ! -e ${RUNNER_DATA_DIR}/.ssh/id_rsa.pub ]; then
    rm -rf ${RUNNER_DATA_DIR}/.ssh/id_rsa ${RUNNER_DATA_DIR}/.ssh/id_rsa.pub
    echo "Generating SSH deploy keys..."
    ssh-keygen -q -t rsa -N "" -f ${RUNNER_DATA_DIR}/.ssh/id_rsa
fi

# Fix directories permissions
chown -R gitlab-runner:gitlab-runner $RUNNER_BUILDS_DIR $RUNNER_CACHE_DIR $RUNNER_WORK_DIR $RUNNER_DATA_DIR
chmod 700 ${RUNNER_DATA_DIR}/.ssh
chmod 700 ${RUNNER_DATA_DIR}/.docker
chmod 600 ${RUNNER_DATA_DIR}/.ssh/id_rsa
chmod 600 ${RUNNER_DATA_DIR}/.ssh/id_rsa.pub
ln -sf ${RUNNER_DATA_DIR}/.ssh ${RUNNER_DIR}/.ssh

# Print the environment for debugging purposes
echo "==> Printing the environment"
env

# Launch Docker daemon
# taken from https://github.com/mesosphere/jenkins-dind-agent/blob/master/wrapper.sh

# Check for DOCKER_EXTRA_OPTS. If not present set to empty value
if [ -z ${DOCKER_EXTRA_OPTS+x} ]; then
    echo "==> Not using DOCKER_EXTRA_OPTS"
    DOCKER_EXTRA_OPTS=
else
    echo "==> Using DOCKER_EXTRA_OPTS"
    echo ${DOCKER_EXTRA_OPTS}
fi

echo "==> Launching the Docker daemon..."
dind dockerd --host=unix:///var/run/docker.sock --storage-driver=${DOCKER_STORAGE_DRIVER:=aufs} $DOCKER_EXTRA_OPTS &

# Wait for the Docker daemon to start
while(! docker info > /dev/null 2>&1); do
    echo "==> Waiting for the Docker daemon to come online..."
    sleep 1
    if [ ! -e /var/run/docker.pid ];then
        echo "==> FATAL : dockerd failed to start"
        exit 1
    fi
done
echo "==> Docker Daemon is up and running!"

# If $HOST and $PORT0 are defined, export METRICS_SERVER env
if [ ! -z ${HOST+x} ] && [ ! -z ${PORT0+x} ];then
    export METRICS_SERVER="$HOST:$PORT0"
fi

# Register the runner
echo "==> Try to register the runner"
gitlab-runner register -n ${RUNNER_NAME}

# Display the config generated
echo "==> Configuration file generated by the registration"
cat ${CONFIG_FILE}

# Display deploy key
echo "==> Deploy key used by this runner:"
cat ${RUNNER_DATA_DIR}/.ssh/id_rsa.pub

# Start the runner
echo "==> Start runner:"
gitlab-runner run --user=gitlab-runner=gitlab-runner --working-directory=${RUNNER_WORK_DIR} "$@"
