#!/bin/bash
# Pomodoro systray icon app

#Change to real local dir
file="${BASH_SOURCE[0]}"
[[ -L $file ]] && path="$(readlink "$file")" || path="$file"
dir="${path%/*}"
cd "$dir"

pomodoro_trayicon () {
    #messages to API
    readonly API=/dev/shm/pomodoro
    #messages between pomodoro-*
    readonly MSG=/dev/shm/pomodoro.msg
    readonly LOCK=/dev/shm/pomodoro.lock
    readonly PID=/dev/shm/pomodoroapp.pid
    readonly APP=/dev/shm/pomodoro.app
    readonly ICON_STARTED=images/iconStarted-0.png
    readonly MENU='Change task!bash -c change_task!edit-paste|Stop!bash -c "daemon stop"!process-stop|Reset!bash -c "daemon reset"!edit-redo|Take a break!bash -c "daemon take_break"!alarm-symbolic|Close trayicon!bash -c quit!application-exit'
    local response=
    
    [[ ! -p $APP ]] && { echo "Daemon not running"; return; }

    systray() {
        exec 3<> $APP
        echo "$1" >&3
    }

    daemon() {
        while true;do
            { #mutex $LOCK to read from $API
                flock -w 5 -x 7 || { echo "Couldn't acquire the lock" >&2; continue; }
                echo $1 > $API 
                break
            } 7>$LOCK
        done
        #nasty timing
        sleep 0.5
        if [[ $1 == status ]]; then
            response=$(<$MSG)
            systray "tooltip:$response" 
        else
            daemon status 
        fi
    }

    change_task() {
        ./change_task_form.sh
        #Update status
        daemon status
    }

    quit() {
        notify-send "Remember to quit the daemon with the client" -t 5000
        systray "quit"
    }

    # Action on left mouse click
    left_click() {
        daemon status 
        [[ $response = started* ]] && daemon pause || daemon start
    }

    export -f left_click daemon quit systray change_task
    export MSG API LOCK ICON_STARTED APP MENU response

    # Attach FD to APP for reading/write (nonblock)
    exec 3<> $APP

    # Lock it up and tell yad to read its stdin from FD
    flock -xn $PID yad --notification --listen --kill-parent \
        --text-align=center --no-middle \
        --text="pomodoroTasks" \
        --image="$ICON_STARTED" \
        --menu="$MENU" \
        --command="bash -c left_click" <&3 || echo "${0##*/} already running" &

    #Update the trayicon
    daemon status
}

pomodoro_trayicon
