#!/usr/bin/env bash
#Simple client for pomodoro-daemon.sh
readonly API=/dev/shm/pomodoro
readonly LOCK=/dev/shm/pomodoro.lock

call() {
    while true;do
        {
            flock -w 5 -x 39 || { echo "Couldn't acquire the lock" >&2; continue; }
            echo $1 > $API 
            break
        } 39>$LOCK
    done
    echo "done  $1"
    sleep 0.1
}


echo starting
date

call start
call status
call status

date
echo done! 
