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
[started-stop]=do_stop
[started-start]=do_warning 
[started-pause]=do_pause 
[started-stop]=do_stop
[started-reset]=do_reset
[started-timeout]=do_increment
[started-status]=do_status
[paused-start]=do_start
[paused-stop]=do_stop
[paused-reset]=do_reset
[paused-pause]=do_warning
[paused-status]=do_status
[stopped-start]=do_start
[stopped-stop]=do_warning
[stopped-reset]=do_reset
[stopped-status]=do_status
[started-dry_start]=do_warning 
[started-dry_stop]=do_dry_stop
[stopped-dry_start]=do_dry_start
[paused-dry_start]=do_dry_start
[stopped-dry_stop]=do_warning
[started-take_break]=do_timeout
[paused-take_break]=do_timeout
[stopped-take_break]=do_timeout
)


#For unit testing pass some number>0  (normally 1)
#so It will work in that number of seconds than 60
testing=$1
#messages to API
readonly API=/dev/shm/pomodoro
#messages between pomodoro-*
readonly MSG=/dev/shm/pomodoro.msg
#mutex (to read API)
readonly LOCK=/dev/shm/pomodoro.lock
# pipe to work with trayicon
readonly APP=/dev/shm/pomodoro.app
#lock app (only one at a time)
readonly PID=/dev/shm/pomodoroapp.pid
#messages with on-hook.pomodoro (taskwarrior hook)
readonly NOHOOK=/dev/shm/pomodoro.onhook
#timeout pomodoro (minutes)
readonly TIMER_POMODORO=25
#break time pomodoro (minutes)
readonly SHORT_TIME_BREAK=5
#long break time pomodoro (minutes)
readonly LONG_TIME_BREAK=15
#Number of breaks to take a long break (LONG_TIME_BREAK)
readonly MAXBREAKS=4
#timeout wait for events (seconds)
readonly TIMEOUT=${testing:-60}
#Counter for breaks
BREAKS=0
>$API

#Global default values
date=$(date +%s)
#Total time elapsed
time_elapsed=0
last_task_id=
STATE=

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
    \rm -f $APP $API $LOCK $NOHOOK $MSG
    exit $?
}

trap clean_up SIGHUP SIGINT SIGTERM 

#Show a timeout splash screen with a progress bar to let the user take a break
do_timeout() {
    #Stop current task
    do_stop
    #Start tracking pomodoro_timeout with timewarrior
    timew start 'pomodoro_timeout' +nowork
    #Increment number of breaks it
    ((BREAKS++))
    local left=$SHORT_TIME_BREAK
    local msg=' --field=$"<b>Go away you fool\!</b>(break $BREAKSº)":LBL '
    #Long break if $BREAKS
    if ((BREAKS == MAXBREAKS));then
        left=$LONG_TIME_BREAK
        msg=' --field=$"<b>Super rest\!</b>($LONG_TIME_BREAK minutes)":LBL '
        BREAKS=0
    fi
    [[ -n $testing ]] && ((left*=10)) || ((left*=60))

    #Check for reminders
    local reminders= ret=
    reminders=$(./reminder-to-yad.py)

    #if there are any reminder show then in a different dialog
    if [[ $reminders ]]; then
        local general="  --window-icon=images/iconStarted-0.png --on-top --sticky  --center --undecorated --title=PomodoroTasks" 
        local timeout="  --timeout=$left --timeout-indicator=bottom "
        local image=" --image-on-top --image=images/pomodoro.png" 
        local selected=

        #launch the dialog and record the last select row in selected
        selected=$(./reminder-to-yad.py | yad --list  --expand-column=2 $general $timeout  $image \
            --buttons-layout=center --button="Back to work"!face-crying:0  \
            --select-action 'bash -c "null=\"%s\" "' \
            --column "ID":HD --column "Description" --column "Due Date"   --column "Done":CHK )
        ret=$?

        #the user has selected any row
        if [[ $selected ]]; then
            task_id=${selected%%|*}
            chk=${selected##*[0-9]|}
            chk=${chk:: -1}
            [[ $chk == TRUE ]] && task $task_id done
        fi
    else #no reminders normal dialog then
        local general='  --window-icon=images/iconStarted-0.png --on-top --sticky  --center --undecorated --title=PomodoroTasks' 
        local timeout='  --timeout=$left --timeout-indicator=bottom '
        local forms=' --align=center --form'
        local image=' --image-on-top --image=images/pomodoro.png' 
        local buttons='  --buttons-layout=center --button="Back to work"!face-crying:0  '
        STATE=do_timeout
        date=0
        time_elapsed=0
        eval yad $general $timeout  $image $buttons $forms $msg
        ret=$?
    fi

    #The user hit the back to work button!
    if (($ret==0));then
        #Stop tracking pomodoro_timeout with timewarrior
        timew stop 
        do_start
    else #the user didn't hit the back to work button
        image=' --image-on-top --image=images/clock.png' 
        buttons=' --buttons-layout=center --button="Yes(default)"!gtk-yes:0  --button="No"!gtk-no:1 '
        msg=' --field=$"<b>Do you want to restart pomodoroTasks?</b>":LBL '
        eval yad $general $image $buttons $forms $msg
        local ret=$?
        #Stop tracking pomodoro_timeout with timewarrior anyway
        timew stop 
        (($ret==0)) && do_start || do_stop
    fi
}

get_active_task() { 
    local active_id
    case $STATE in
        pause*|stop*) active_id=$last_task_id
            ;;
        *           ) active_id=$(task +ACTIVE uuids)
            ;;
    esac
    [[ -z $active_id ]] && { echo "\nBreak $BREAKSº.No active task"; return; }
    #Show the numbers of breaks and the total active time if tracked
    local total=$(task _get $active_id.totalactivetime)
    readonly desc=$(task _get $active_id.description)
    readonly proj=$(task _get $active_id.project)

    [[ -n $total ]] && total+=" total active time"
    case $STATE in
        pause*|stop*) echo "\nBreak $BREAKSº. $total\nLast Project($active_id):$proj\n$desc\n" 
            ;;
        *           ) echo "\nBreak $BREAKSº. $total\nProject:$proj\n$desc\n" 
            ;;
    esac
}

do_warning() { echo "Already $STATE" >$MSG; }

do_status() { echo "$STATE $((TIMER_POMODORO - time_elapsed)) minutes left $(get_active_task)" >$MSG; }

systray() {
    flock -xn $PID true || 
    {
        #nonblocking <>
        exec 3<> $APP
        echo "$1" >&3
    }
}

update_trayicon(){
    local left=$((TIMER_POMODORO - time_elapsed))
    local rest=$((TIMER_POMODORO / 8))
    local actual=$(( time_elapsed / rest ))
    local ICON_STARTED=images/iconStarted-$actual.png
    local ICON_PAUSED=images/iconPaused.png
    local ICON_STOPPED=images/iconStopped.png
    #Update trayicon tooltip 
    systray "tooltip:$STATE $left minutes left $(get_active_task)" 

    case $STATE in
        start*) systray icon:$ICON_STARTED 
            ;;
        pause*) systray icon:$ICON_PAUSED 
            ;;
        stop*)  systray icon:$ICON_STOPPED 
            ;;
    esac
}

do_increment() {
    ((time_elapsed++))
    (( time_elapsed >= TIMER_POMODORO )) && do_timeout
    update_trayicon
}

#Save last task after going to pause/stop to account proper work time on a task
save_last_task() {
    local check_id
    case $STATE in 
        pause*|stop*) 
            check_id=$(task +ACTIVE uuids) 
            [[ -n $check_id ]]  && last_task_id=$check_id
            ;; 
        *           ) 
            last_task_id=$(task +ACTIVE uuids) 
            ;; 
    esac
    [[ -z $last_task_id ]] && { return; }
    if [[ -z $1 ]]; then
        #Disable the on-modify.pomodoro taskwarrior hook (loop)
        touch $NOHOOK
        task $last_task_id stop
        #Enable
        \rm -f $NOHOOK
    fi
}

do_dry_start() {
    #Don't update time_elapsed when paused
    [[ $STATE == stopped ]] && time_elapsed=0 
    STATE=started
    date=$(date +%s)
    # Can't get the id cause it's activated on taskwarrior hook, so no active already
    # wait 1 minute to refresh (TODO)
    update_trayicon
}

do_start() {
    local check_id=$(task +ACTIVE uuids) 
    #If resumed from pause/stop without changing the current task from GUI
    if [[ -n $last_task_id && -z $check_id ]]; then
        #Disable the on-modify.pomodoro taskwarrior hook (loop)
        touch $NOHOOK
        task $last_task_id start
        #Enable
        \rm -f $NOHOOK
    else
        last_task_id=$check_id
    fi

    #Don't update time_elapsed when paused
    [[ $STATE == stopped ]] && time_elapsed=0 
    STATE=started
    date=$(date +%s)
    update_trayicon
}


do_pause() {
    STATE=paused
    save_last_task
    update_trayicon
}

do_dry_stop() {
    STATE=stopped
    date=0
    time_elapsed=0
    save_last_task dry
    update_trayicon
}

do_stop() {
    #save before update STATE
    save_last_task
    STATE=stopped
    date=0
    time_elapsed=0
    update_trayicon
}

do_reset() {
    STATE=stopped
    BREAKS=0
    do_start
}


#Call initial STATE
already=$(task +ACTIVE uuids)

#launch trayicon app before do_anything
"$dir/pomodoro-trayicon.sh" &

#set the initial STATE to the real STATE
[[ -z $already ]] && do_stop || do_start 


#Launch daemon
while true; do
    #wait TIMEOUT seconds or a new msg
    inotifywait -e modify $API -t $TIMEOUT &> /dev/null
    ret=$?
    { #mutex $LOCK (FD 7) to read/write API and do the event
        if (($ret == 0)); then
            #Should check several times otherwise quit
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
        command=${events[$STATE-$event]}
        [[ -z $command ]] && continue
        $command 
    } 7>$LOCK
done



