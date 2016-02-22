#!/bin/bash
# Pomodoro systray icon app

pomodoro_trayicon () {
    readonly API=/dev/shm/pomodoro
    readonly LOCK=/dev/shm/pomodoro.lock
    readonly ICON_STARTED=images/iconStarted.png
    readonly ICON_PAUSED=images/iconPaused.png
    readonly ICON_STOPPED=images/iconStopped.png
    readonly FIFO=/dev/shm/pomodoro.app
    readonly MENU='Change task!bash -c change_task!emblem-default|Stop!bash -c "daemon stop"!process-stop|Quit!bash -c quit!application-exit'
    local state=
    
    [[ ! -p $FIFO ]] && { echo "Daemon not running"; return; }

    systray() {
        exec 3<> $FIFO
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
        sleep 0.1
        if [[ $1 == status ]]; then
            state=$(<$API)
            exec 3<> $FIFO
            echo "tooltip:$state" >&3
            case $state in
                start*) systray icon:$ICON_STARTED ;;
                pause*) systray icon:$ICON_PAUSED ;;
                 stop*) systray icon:$ICON_STOPPED ;;
            esac
        else
            daemon status 
        fi
    }

    change_task() {
        ./change_task_form.sh
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
    export API LOCK ICON_STARTED ICON_PAUSED ICON_STOPPED FIFO MENU state

    # Attach FD to FIFO for reading/write (nonblock)
    exec 3<> $FIFO


    # Tell yad to read its stdin from FD
    yad --notification --listen --kill-parent \
        --text-align=center --no-middle \
        --text="pomodoroTasks" \
        --image="$ICON_STARTED" \
        --menu="$MENU" \
        --command="bash -c left_click" <&3 &

    #Update the trayicon
    daemon status
}

pomodoro_trayicon
