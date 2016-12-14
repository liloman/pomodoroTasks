#!/usr/bin/env bash
# Pomodoro daemon with FSM

#Change to real local dir
file="${BASH_SOURCE[0]}"
[[ -L $file ]] && path="$(readlink "$file")" || path="$file"
dir="${path%/*}"
cd "$dir"

needs() { hash $1 &>/dev/null || { echo "Needs $1" >&2; exit 1; } }
needs flock
needs inotifywait
needs yad
#Taskwarrior
needs task
#Timewarrior
needs timew


#Finite State Machine logic (FSM)
declare -A events
# [from-event]=to
events=(
[started-start]=warning 
[started-pause]=paused 
[started-stop]=stopped
[started-reset]=resetted
[started-timeout]=increment
[started-status]=status
[paused-start]=started
[paused-stop]=stopped
[paused-reset]=resetted
[paused-pause]=warning
[paused-status]=status
[stopped-start]=started
[stopped-stop]=warning
[stopped-reset]=resetted
[stopped-status]=status
)


#For unit testing pass some number>0  (normally 1)
#so It will work in that number of seconds than 60
testing=$1
#messages
readonly API=/dev/shm/pomodoro
#mutex
readonly LOCK=/dev/shm/pomodoro.lock
# pipe to work with trayicon
readonly APP=/dev/shm/pomodoro.app
#lock app
readonly PID=/dev/shm/pomodoroapp.pid
#timeout pomodoro (minutes)
readonly TIMER1=25
#break time pomodoro (minutes)
readonly TIMER2=5
#long break time pomodoro (minutes)
readonly TIMER3=15
#Number of breaks to take a long break (TIMER3)
readonly MAXBREAKS=4
#timeout wait for events (seconds)
readonly TIMEOUT=${testing:-60}
#Counter for breaks
BREAKS=0
>$API

#Global default values
state=stopped
date=$(date +%s)
total=0
last_task_id=

[[ -p $APP ]] && { echo "Daemon already running"; exit 1; }
mkfifo $APP

clean_up() {
    echo cleanning up...
    exec 3<> $APP
    #Close trayicon app
    echo "quit" >&3
    #Close pipe
    exec 3>&-
    sleep 1
    \rm $APP $API $LOCK
    exit $?
}

trap clean_up SIGHUP SIGINT SIGTERM 

locked() {
    #Stop and stop current task
    stopped
    #Start tracking pomodoro_timeout with timewarrior
    timew start 'pomodoro_timeout'
    #Increment number of breaks it
    ((BREAKS++))
    local left=$TIMER2
    local msg=' --field=$"<b>Go away you fool\!</b>(break $BREAKSº)":LBL '
    #Long break if $BREAKS
    if ((BREAKS == MAXBREAKS));then
        left=$TIMER3
        msg=' --field=$"<b>Super rest\!</b>($TIMER3 minutes)":LBL '
        BREAKS=0
    fi
    [[ -n $testing ]] && ((left*=10)) || ((left*=60))
    readonly general='  --window-icon=images/iconStarted.png --on-top --sticky  --center --undecorated --title=PomodoroTasks' 
    readonly timeout='  --timeout=$left --timeout-indicator=bottom '
    readonly forms=' --align=center --form'
    local image=' --image-on-top --image=images/pomodoro.png' 
    local buttons='  --buttons-layout=center --button="Back to work"!face-crying:0  '
    state=locked
    date=0
    total=0
    eval yad $general $timeout  $image $buttons $forms $msg
    local ret=$?
    if (($ret==0));then
        #Stop tracking pomodoro timeout with timewarrior
        timew stop 
        started
    else #the user didn't hit the back to work button
        image=' --image-on-top --image=images/clock.png' 
        buttons=' --buttons-layout=center --button="Yes(default)"!gtk-yes:0  --button="No"!gtk-no:1 '
        msg=' --field=$"<b>Do you want to restart pomodoroTasks?</b>":LBL '
        eval yad $general $image $buttons $forms $msg
        local ret=$?
        #Stop tracking pomodoro_timeout with timewarrior anyway
        timew stop 
        (($ret==0)) && started || stopped
    fi
}

get_active_task() { 
    local active_id
    case $state in
        pause*|stop*) active_id=$last_task_id
            ;;
        *           ) active_id=$(task +ACTIVE ids)
            ;;
    esac
    [[ -z $active_id ]] && { echo "\nNo active task"; return; }
    readonly desc=$(task _get $active_id.description)
    readonly proj=$(task _get $active_id.project)
    case $state in
        pause*|stop*) echo "\nLast Project($active_id):$proj\n$desc\n" 
            ;;
        *           ) echo "\nProject:$proj\n$desc\n" 
            ;;
    esac
}

warning() { echo "Already $state" >$API; }

status() { echo "$state $((TIMER1 - total)) minutes left $(get_active_task)" >$API; }

systray() {
    flock -xn $PID true || 
    {
        #nonblocking <>
        exec 3<> $APP
        echo "$1" >&3
    }
}

update_trayicon(){
    local ICON_STARTED=images/iconStarted.png
    local ICON_PAUSED=images/iconPaused.png
    local ICON_STOPPED=images/iconStopped.png
    #Update trayicon tooltip 
    systray "tooltip:$state $((TIMER1 - total)) minutes left $(get_active_task)" 

    case $state in
        start*) systray icon:$ICON_STARTED 
            ;;
        pause*) systray icon:$ICON_PAUSED 
            ;;
        stop*)  systray icon:$ICON_STOPPED 
            ;;
    esac
}

increment() {
    ((total++))
    (( total >= TIMER1 )) && locked
    update_trayicon
}

started() {
    local check_id=$(task +ACTIVE ids) 
    #If resumed from pause/stop without changing the current task from CLI/X
    if [[ -n $last_task_id && -z $check_id ]]; then
        task $last_task_id start
    else
        last_task_id=$check_id
    fi
    #Don't update total when paused
    [[ $state == stopped ]] && total=0 
    state=started
    date=$(date +%s)
    update_trayicon
}

#Save last task after going to pause/stop to account proper work time on a task
save_last_task() {
    local check_id
    case $state in 
        pause*|stop*) 
            check_id=$(task +ACTIVE ids) 
            [[ -n $check_id ]]  && last_task_id=$check_id
            ;; 
        *           ) 
            last_task_id=$(task +ACTIVE ids) 
            ;; 
    esac
    [[ -z $last_task_id ]] && { return; }
    task $last_task_id stop
}

paused() {
    state=paused
    save_last_task
    update_trayicon
}

stopped() {
    state=stopped
    date=0
    total=0
    save_last_task
    update_trayicon
}

resetted() {
    state=stopped
    BREAKS=0
    started
}

#Call initial state
$state

#launch trayicon app
"$dir/pomodoro-trayicon.sh" &

#Launch daemon
while true; do
    #wait TIMEOUT seconds or a new msg
    inotifywait -e modify $API -t $TIMEOUT &> /dev/null
    ret=$?
    { #mutex $LOCK (FD 7) to read/write API and do the event
        if (($ret == 0)); then
            flock -w 5 -x 7 || { echo "Couldn't acquire the lock" >&2; continue; }
            event=$(<$API)
            >$API
            [[ $event = quit ]] && clean_up
            #Timeout event
        elif (($ret == 2)); then
            event=timeout
        else
            continue
        fi
        command=${events[$state-$event]}
        [[ -z $command ]] && continue
        $command
    } 7>$LOCK
done



