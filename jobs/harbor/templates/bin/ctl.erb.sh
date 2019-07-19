#!/bin/bash

set -e # exit immediately if a simple command exits with a non-zero status
set -u # report the usage of uninitialized variables
set -o pipefail

source /var/vcap/packages/common/utils.sh

JOB_NAME=harbor
HARBOR_RUN_DIR=$RUN_DIR/$JOB_NAME
HARBOR_LOG_DIR=$LOG_DIR/$JOB_NAME
HARBOR_JOB_DIR=$JOB_DIR/$JOB_NAME
PIDFILE=${HARBOR_RUN_DIR}/harbor.pid
TEMP_PIDFILE=${HARBOR_RUN_DIR}/harbor.tmp.pid
HARBOR_PACKAGE_DIR=${PACKAGE_DIR}/harbor-app
COMPOSE_PACKAGE_DIR=${PACKAGE_DIR}/docker-compose
HARBOR_YAML=${HARBOR_PACKAGE_DIR}/docker-compose.yml

CTL_CMD=/sbin/start-stop-daemon
COMPOSE_CMD=${COMPOSE_PACKAGE_DIR}/bin/docker-compose
DAEMON_SOCK=${RUN_DIR}/docker/dockerd.sock
DAEMON_PID=${RUN_DIR}/docker/dockerd.pid
CRON_PATH=/etc/cron.d/$JOB_NAME
CRON_JOB_INTERVAL=2
CHECK_SCRIPT_PATH=${HARBOR_JOB_DIR}/bin/status_check

COMMAND_NAME=$1

#Make sure folders are ready
for dir in $HARBOR_RUN_DIR $HARBOR_LOG_DIR ; do
  mkdir -p ${dir}
  chown vcap:vcap ${dir}
  chmod 755 ${dir}
done

#Add symbol link to harbor logs dir, then 'bosh logs' can collect them.
ln -sfT /var/log/harbor $HARBOR_LOG_DIR/harbor-app-logs

#Workaround to resolve the docker-compose libz issue
sudo mount /tmp -o remount,exec

exec 1>> $HARBOR_LOG_DIR/ctl.stdout.log
exec 2>> $HARBOR_LOG_DIR/ctl.stderr.log

source $PACKAGE_DIR/harbor-common/common.sh
source $HARBOR_JOB_DIR/bin/properties.sh

#Start the harbor process
#Require options parameter for $COMPOSE_CMD
startHarbor() {
  $CTL_CMD --pidfile $TEMP_PIDFILE \
  --make-pidfile \
  --background \
  --start --oknodo \
  --startas /bin/bash \
  -- -c "$COMPOSE_CMD $1 1>> $HARBOR_LOG_DIR/ctl.stdout.log 2>&1"
  #Wait for a while to let docker-compose initialize
  sleep 5
}

#Stop the harbor process
stopHarbor() {
  $COMPOSE_CMD $1 2>&1 &
  pid=$!
  # monit will use pid in $PIDFILE to check if harbor job is stopped,
  # then stop dockerd job if running 'monit stop all'.
  echo $pid > $PIDFILE
  wait $pid
  rm -f $PIDFILE $TEMP_PIDFILE
}

waitForHarbor() {
  sleep_time=5
  timeout=180
  count=0
  log "Waiting for Harbor Service to be ready ..."
  while ! $CHECK_SCRIPT_PATH >> $HARBOR_LOG_DIR/cron.log 2>&1
  do
    log "Harbor service is not ready. Waiting for $sleep_time seconds then check again."
    sleep $sleep_time
    count=$((count + sleep_time));
    if [ $count -ge $timeout ]; then
      log "Error: Harbor Service failed to start in $timeout seconds."
      exit 1
    fi
  done
  log "Harbor Service is ready"
}

#Check docker daemon status
checkDockerdStatus() {
  [[ -e $DAEMON_SOCK ]] && \
  [[ -e $DAEMON_PID ]] && \
  pgrep -f dockerd >/dev/null 2>&1
}

#Add cron job to check Harbor service availability.
#If harbor service is not running well, remove the harbor pid file, then monit will restart it.
cronJobUp() {
  echo "*/$CRON_JOB_INTERVAL * * * * root $CHECK_SCRIPT_PATH -r >> $HARBOR_LOG_DIR/cron.log 2>&1" > $CRON_PATH
}

#Stop the cron job
cronJobDown() {
  rm -f $CRON_PATH
}

#Build compose options
COMPOSE_OPTS="-H $DOCKER_HOST -f ${HARBOR_YAML}"

case $COMMAND_NAME in

  start)
    log "Starting Harbor $HARBOR_FULL_VERSION at ${HARBOR_PROTOCOL}://${HARBOR_HOSTNAME}"

    waitForDockerd

    #Dead harbor containers will prevent Harbor service to start.
    log "Remove dead docker containers if exist"
    $DOCKER_CMD ps -aq -f 'status=dead'

    log "Launching 'docker-compose up' ..."
    COMPOSE_OPTS="${COMPOSE_OPTS} up"
    startHarbor "$COMPOSE_OPTS"

    #Wait for Harbor Service
    waitForHarbor
    #Now let monit detect the real harbor pid. Keep the TEMP_PIDFILE to be detected by startHarbor().
    cp $TEMP_PIDFILE $PIDFILE

    log "Add cron job for Harbor status check"
    cronJobUp
    ;;

  stop)
    log "Stopping Harbor ..."
    log "Remove cron job for Harbor status check"
    cronJobDown

    #TODO: Add instance clean work here if migration is enabled

    log "Launching 'docker-compose down' ..."
    COMPOSE_OPTS="${COMPOSE_OPTS} down"
    stopHarbor "$COMPOSE_OPTS"
    ;;

  *)
    log -n "Usage: ctl {start|stop}"
    ;;

esac

log "ctl $COMMAND_NAME is successfully done!"
exit 0
