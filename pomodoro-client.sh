#!/usr/bin/env bash
#Simple client for pomodoro-daemon.sh

#messages to API
readonly API=/dev/shm/pomodoro
#messages between pomodoro-*
readonly MSG=/dev/shm/pomodoro.msg
readonly LOCK=/dev/shm/pomodoro.lock
readonly APP=/dev/shm/pomodoro.app

call() {

    while true;do
        {
            flock -w 5 -x 7 || { echo "Couldn't acquire the lock" >&2; continue; }
            echo $1 > $API 
            break
        } 7>$LOCK
    done
    #wait for response
    sleep 0.1
    echo -e $(<$MSG)
}

#Dont suggest potentialy wrong options dry_start and dry_stop 
usage() { echo "Unknown option: try start,pause,stop,reset,status,take_break or quit to close the daemon"; }

com() {
    [[ ! -p $APP ]] && { echo "Daemon not running"; return; }
    call $1
    # [[ $1 != status && $1 != quit ]] && call status
}

case $1 in
    start|pause|stop|reset|status|quit|dry_start|dry_stop|take_break)  com $1
        ;;
    *                           ) usage
        ;;
esac

