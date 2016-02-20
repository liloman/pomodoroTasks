#!/bin/bash
# Pomodoro systray icon app

pomodoro_trayicon () {
    readonly API=/dev/shm/pomodoro
    readonly LOCK=/dev/shm/pomodoro.lock
    readonly ICON_STARTED=images/iconStarted.png
    readonly ICON_PAUSED=images/iconPaused.png
    readonly ICON_STOPPED=images/iconStopped.png
    readonly FIFO=/dev/shm/pomodoro.app
    local last=
    do_call() {
        while true;do
            {
                flock -w 5 -x 7 || { echo "Couldn't acquire the lock" >&2; continue; }
                echo $1 > $API 
                break
            } 7>$LOCK
        done
        sleep 0.1
        if [[ $1 == status ]]; then
            exec 3<> $FIFO
            last=$(<$API)
            echo "tooltip:$last" >&3
            >$API
        fi
    }

    change_task() {
        exec 3<> $FIFO
        echo "icon:$1" >&3
        >$API
    }

    change_icon() {
        exec 3<> $FIFO
        echo "icon:$1" >&3
        >$API
    }

    do_start() {
        do_call start
        do_call status
        change_icon $ICON_STARTED
    }

    do_pause() {
        do_call pause
        do_call status
        change_icon $ICON_PAUSED
    }

    do_stop() {
        do_call stop
        do_call status
        change_icon $ICON_STOPPED
    }

    do_status() {
        do_call status
    }

    do_quit() {
        exec 3<> $FIFO
        echo quit >&3
    }

    # Action on left mouse click
    left_click() {
        do_call status
        [[ $last = started* ]] && do_pause || do_start
    }

    export -f left_click 
    export -f do_call do_pause do_start do_status do_quit do_stop 
    export -f change_icon change_task
    export API LOCK ICON_STARTED ICON_PAUSED FIFO last

    # Attach FD to FIFO
    mkfifo $FIFO
    exec 3<> $FIFO

    # Tell yad to read its stdin from FD
    $(yad --notification --kill-parent --listen \
        --image="$ICON_STARTED" \
        --no-middle \
        --command="bash -c left_click" <&3 ) &

    # Generate MENU 
    echo  "menu:Change task!bash -c change_task!task-due|Stop!bash -c do_stop!process-stop|Quit!bash -c do_quit!application-exit" >&3
    do_call status
}

pomodoro_trayicon
