#!/usr/bin/env bash
# Pomodoro daemon with FSM

needs() { hash $1 &>/dev/null || { echo "Needs $1" >&2; exit 1; } }
needs inotifywait
needs flock
needs zenity

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
[started-]=increment
[paused-start]=started
[paused-pause]=started
[paused-reset]=stopped
[paused-status]=status
)


#For unit testing pass some number>0
#so It will work in seconds then minutes
testing=${1:-0}
readonly API=/dev/shm/pomodoro
#timeout pomodoro (minutes)
readonly TIMER1=25
#break time pomodoro (minutes)
readonly TIMER2=5
readonly LOCK=/dev/shm/pomodoro.lock
#timeout watch file (seconds)
TIMEOUT=60
\rm -f $LOCK
>$API
((testing)) && TIMEOUT=1

#Global values
state=stopped
date=0
total=0


locked() {
    local resol=($(xrandr --current | grep '*' ))
    local width=${resol[0]%x*}
    local height=${resol[0]#*x}
    local left=$((TIMER2))
    ((testing)) || ((left*=60))
    ((width-=20))
    state=locked
    date=0
    total=0
    {
        for p in {1..100};do
            echo $p
            sleep $((left/100))
        done
    } | zenity --progress --text Break time --auto-close --time-remaining   --no-cancel --modal --width=$width --height=$height --auto-close
    #Stop it 
    stopped
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
    ((testing)) && time=1
    local min=$(( (now - date) / time ))
    state=paused
    ((total+=min))
}

stopped() {
    state=stopped
    date=0
    total=0
}



#Launch daemon
while true; do
    #wait TIMEOUT seconds or a new msg
    inotifywait -e modify $API -t $TIMEOUT &> /dev/null
    {
        flock -w 5 -x 39 || { echo "Couldn't acquire the lock" >&2; continue; }
        event=$(<$API)
        >$API
        next=$state-$event
        command=${events[$next]}
        [[ -z $command ]] && continue
        [[ -n $DEBUG ]] && echo doing:$command 
        $command
    } 39>$LOCK
done


