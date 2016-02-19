#!/usr/bin/env bash
# Pomodoro daemon with FSM

needs() { hash $1 &>/dev/null || { echo "Needs $1" >&2; exit 1; } }
needs flock
needs inotifywait
needs yad

#Finite State Machine logic (FSM)
declare -A events
# [from-event]=to
events=(
[stopped-start]=started
[stopped-reset]=started
[stopped-status]=status
[started-start]=warning 
[started-reset]=stopped
[started-pause]=paused 
[started-stop]=stopped
[started-status]=status
[started-timeout]=increment
[paused-start]=started
[paused-pause]=started
[paused-reset]=stopped
[paused-status]=status
)


#For unit testing pass some number>0  (normally 1)
#so It will work in that number of seconds than 60
testing=$1
readonly API=/dev/shm/pomodoro
readonly LOCK=/dev/shm/pomodoro.lock
#timeout pomodoro (minutes)
readonly TIMER1=25
#break time pomodoro (minutes)
readonly TIMER2=5
#timeout wait for events (seconds)
readonly TIMEOUT=${testing:-60}
>$API

#Global default values
state=started
date=0
total=0

locked() {
    local left=$((TIMER2))
    [[ -n $testing ]] && ((left*=10)) || ((left*=60))
    local general=' --model --on-top --sticky  --center --undecorated --title=PomodoroBash' 
    local timeout='  --timeout=$left --timeout-indicator=bottom '
    local image=' --image-on-top --image=images/pomodoro.png' 
    local buttons='  --buttons-layout=center --button="Back to work"!face-crying:0  '
    local forms=' --align=center --form'
    local msg=' --field=$"<b>Go away you fool\!</b>":LBL '
    state=locked
    date=0
    total=0
    eval yad $general $timeout  $image $buttons $forms $msg
    local ret=$?
    if (($ret==0));then
        started
    else #the user didn't hit the back to work button
        image=' --image-on-top --image=images/clock.png' 
        buttons=' --buttons-layout=center --button="Restart(default)"!gtk-yes:0  --button="Stop it"!gtk-no:1 '
        msg=' --field=$"<b>Do you want to restart pomodoroBash?</b>":LBL '
        eval yad $general $image $buttons $forms $msg
        local ret=$?
        if (($ret==0));then
            started
        else
            stopped
        fi
    fi
}

warning() { echo "Already started"; }

status() {
    echo state:$state
    echo "$((TIMER1 - total)) minutes left"
}

increment() {
    ((total++))
    (( total == TIMER1 )) && locked
}

started() {
    state=started
    date=$(date +%s)
    total=0
}

paused() {
    local now=$(date +%s)
    local time=60
    [[ -n $testing ]] && time=$testing
    local min=$(( (now - date) / time ))
    state=paused
    ((total+=min))
}

stopped() {
    state=stopped
    date=0
    total=0
}


#Call initial state
$state
#Launch daemon
while true; do
    #wait TIMEOUT seconds or a new msg
    inotifywait -e modify $API -t $TIMEOUT &> /dev/null
    ret=$?
    { #mutex on FD 39 $LOCK
        if (($ret == 0)); then
            flock -w 5 -x 39 || { echo "Couldn't acquire the lock" >&2; continue; }
            event=$(<$API)
            #Timeout event
        elif (($ret == 2)); then
            event=timeout
        fi
        command=${events[$state-$event]}
        [[ -z $command ]] && continue
        $command
    } 39>$LOCK
done


