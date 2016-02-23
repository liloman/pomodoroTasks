#!/usr/bin/env bash

#Show change task form
function change_task_form() {
readonly current_task_id=$(task +ACTIVE ids)

sanitize() {
    local arg="$1"
    arg="${arg//\#/}"
    arg="${arg//|/}"
    echo "$arg"
}

get_tasks() {
    local project=
    local description=
    #Get taskwarrior list and skip header
    for id in $(task _ids); do
        #Skip current active task
        [[ $current_task_id == $id ]] && continue
        project=$(task _get $id.project)
        description=$(task _get $id.description)
        tasks+="$id \[$project\]-$description#"
    done
    #Remove last #
    echo -n "${tasks%#}"
}

add_new_task(){
    readonly sets2=' --title="Add new task" --text="Fill at least description (not allowed # or |)" '
    readonly form2=" --form --item-separator='#' --align=right "
    readonly buttons2=' --button="Add#gtk-apply#0" --button="Cancel#gtk-cancel#1" '
    local projects="None#"
    local project=
    local description=
    local ret=
    #Read with spaces
    while IFS= read -r project; 
    do 
        projects+="$project#"; 
    done <<< "$(task _projects)"
    projects="${projects%#}"
    readonly fields=" --field Description '' --field Project:CBE '$projects' "

    #Execute it
    ret=$(eval yad  $general $sets2 $form2 $fields $buttons2)

    (( $? != 0 )) && return
    ret="${ret%|}"

    project=${ret#*|}
    description=${ret%|*}
    #sanitize them
    description=$(sanitize "$description")
    project=$(sanitize "$project")

    [[ -z $description ]] && return
    if [[ $project == None ]];then
        ret=$(task add $description 2>/dev/null)
    else
        ret=$(task add pro:"$project" $description 2>/dev/null)
    fi

    (($? != 0)) && return

    #Remove the last point
    ret=${ret%.}
    #Get the created new task id 
    new_id=${ret##*[[:space:]]};

    # Update the field 1 (CB) with the new CB list values. Selecting the new_id (^)
    echo "1 $tasks#^$new_id [$project]-$description"
}

local tasks="0 ------------------------------------  None ----------------------------------- #"
tasks=$(get_tasks)

readonly general=' --buttons-layout=center --dialog-sep --on-top --window-icon=images/iconStarted.png '
readonly sets=' --title="Change task" --text="Please choose a Task" '
readonly form=" --form --item-separator='#' --align=left --columns=2 "
readonly column1=" --field Tasks:CB '$tasks' --field :LBL --field \"Mark current Task as done\":CHK false --field :LBL "
readonly column2=" 1 2 --field ''#list-add#\"Add new task\":FBTN \"@bash -c add_new_task\" --field :LBL --field ' ':LBL --field :LBL "
readonly buttons=' --button="Change#gtk-apply#0" --button="Cancel#gtk-cancel#1" '

#Export functions/variables for the new yad processes
export -f add_new_task sanitize
export general tasks current_task_id

#Execute change task form
ret=$(eval yad  $general $sets $form  $column1 $column2 $buttons)

#If cancel or escape
(( $? != 0 )) && return 

#Get return values into opt array
IFS='|' opt=($ret)
selected_task_id=${opt[0]%%[[:space:]]*}
selected_done=${opt[2]}

# Not task selected
(( selected_task_id == 0 )) && exit 

if [[ $selected_done == FALSE ]]; then
    task $current_task_id stop &> /dev/null
else
    task $current_task_id done  &> /dev/null
fi

task $selected_task_id start &> /dev/null
}

change_task_form
