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
[started-start]=warning 
[started-pause]=paused 
[started-stop]=stopped
[started-timeout]=increment
[started-status]=status
[paused-start]=started
[paused-stop]=stopped
[paused-pause]=warning
[paused-status]=status
[stopped-start]=started
[stopped-stop]=warning
[stopped-status]=status
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
# pipe to work with the trayicon
readonly FIFO=/dev/shm/pomodoro.app
>$API

#Global default values
state=started
date=$(date +%s)
total=0
mkfifo $FIFO

clean_up() {
    \rm -f $FIFO
}

trap clean_up SIGHUP SIGINT SIGTERM

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

warning() { echo "Already $state" >$API; }

status() { echo "$state $((TIMER1 - total)) minutes left" >$API; }

increment() {
    ((total++))
    (( total >= TIMER1 )) && locked
    #Update trayicon tooltip 
    exec 3<> $FIFO
    echo "tooltip:$state $((TIMER1 - total)) minutes left" >&3
}

started() {
    #Don't update total when paused
    [[ $state == stopped ]] && total=0 
    state=started
    date=$(date +%s)
}

paused() {
    local now=$(date +%s)
    # local time=${testing:-60}
    # local min=$(( (now - date) / time ))
    # ((total+=min))
    state=paused
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



