#!/usr/bin/env bash
#Simple client for pomodoro-daemon.sh
readonly API=/dev/shm/pomodoro
readonly LOCK=/dev/shm/pomodoro.lock

call() {
    while true;do
        {
            flock -w 5 -x 7 || { echo "Couldn't acquire the lock" >&2; continue; }
            echo $1 > $API 
            break
        } 7>$LOCK
    done
    sleep 0.1
    echo $(<$API)
    >$API
}


echo starting
date

#call start
call status
# call status

date
echo done! 
