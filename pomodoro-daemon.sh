#!/usr/bin/env bash
# Pomodoro daemon with FSM

#Change to real local dir
dir="$(readlink $0)"
cd "${dir%/*}"

needs() { hash $1 &>/dev/null || { echo "Needs $1" >&2; exit 1; } }
needs flock
needs inotifywait
needs yad
needs task


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
#messages
readonly API=/dev/shm/pomodoro
#mutex
readonly LOCK=/dev/shm/pomodoro.lock
# pipe to work with trayicon
readonly FIFO=/dev/shm/pomodoro.app
#timeout pomodoro (minutes)
readonly TIMER1=25
#break time pomodoro (minutes)
readonly TIMER2=5
#long break time pomodoro (minutes)
readonly TIMER3=15
#Number of breaks to take a long break (TIMER3)
readonly MAXBREAKS=4
#Counter for breaks
BREAKS=0
#timeout wait for events (seconds)
readonly TIMEOUT=${testing:-60}
>$API

#Global default values
state=started
date=$(date +%s)
total=0

[[ -p $FIFO ]] && { echo "Daemon already running"; exit 1; }
mkfifo $FIFO

clean_up() {
    echo cleanning up...
    exec 3<> $FIFO
    #Close trayicon app
    echo "quit" >&3
    #Close pipe
    exec 3>&-
    sleep 1
    \rm -f $FIFO $API $LOCK
    exit $?
}

trap clean_up SIGHUP SIGINT SIGTERM 

locked() {
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
        started
    else #the user didn't hit the back to work button
        image=' --image-on-top --image=images/clock.png' 
        buttons=' --buttons-layout=center --button="Yes(default)"!gtk-yes:0  --button="No"!gtk-no:1 '
        msg=' --field=$"<b>Do you want to restart pomodoroTasks?</b>":LBL '
        eval yad $general $image $buttons $forms $msg
        local ret=$?
        (($ret==0)) && started || stopped
    fi
}

get_active_task() { 
    readonly id=$(task +ACTIVE ids)
    [[ -z $id ]] && { echo "\nNo active task"; return; }
    readonly desc=$(task _get $id.description)
    readonly proj=$(task _get $id.project)
    echo "\nProject:$proj\n$desc\n" 
}

warning() { echo "Already $state" >$API; }

status() { echo "$state $((TIMER1 - total)) minutes left $(get_active_task)" >$API; }

increment() {
    ((total++))
    (( total >= TIMER1 )) && locked
    #read/write (nonblocking important!)
    exec 3<> $FIFO
    #Update trayicon tooltip 
    echo "tooltip:$state $((TIMER1 - total)) minutes left $(get_active_task)" >&3
}

started() {
    #Don't update total when paused
    [[ $state == stopped ]] && total=0 
    state=started
    date=$(date +%s)
}

paused() {
    state=paused
}

stopped() {
    state=stopped
    date=0
    total=0
}


#Call initial state
$state

#launch trayicon app
./pomodoro-trayicon.sh &

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



