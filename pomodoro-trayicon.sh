#!/bin/bash
# Pomodoro systray icon app

#Change to real local dir
file="${BASH_SOURCE[0]}"
[[ -L $file ]] && path="$(readlink "$file")" || path="$file"
dir="${path%/*}"
cd "$dir"

pomodoro_trayicon () {
    readonly API=/dev/shm/pomodoro
    readonly LOCK=/dev/shm/pomodoro.lock
    readonly PID=/dev/shm/pomodoroapp.pid
    readonly APP=/dev/shm/pomodoro.app
    readonly ICON_STARTED=images/iconStarted.png
    readonly ICON_PAUSED=images/iconPaused.png
    readonly ICON_STOPPED=images/iconStopped.png
    readonly MENU='Change task!bash -c change_task!edit-paste|Stop!bash -c "daemon stop"!process-stop|Reset!bash -c "daemon reset"!edit-redo|Take a break!bash -c "daemon take_break"!alarm-symbolic|Quit!bash -c quit!application-exit'
    local state=
    
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
        sleep 0.3
        if [[ $1 == status ]]; then
            state=$(<$API)
            systray "tooltip:$state" 
            case $state in
                start*) systray icon:$ICON_STARTED 
                    ;;
                pause*) systray icon:$ICON_PAUSED 
                    ;;
                stop* ) systray icon:$ICON_STOPPED
                    ;;
            esac
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
        systray "quit"
    }

    # Action on left mouse click
    left_click() {
        daemon status 
        [[ $state = started* ]] && daemon pause || daemon start
    }

    export -f left_click daemon quit systray change_task
    export API LOCK ICON_STARTED ICON_PAUSED ICON_STOPPED APP MENU state

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
