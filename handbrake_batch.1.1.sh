#!/usr/bin/env bash 
# only checks working directory and makes use of PWD 

declare -g TARGET_DIR="${PWD}" 
declare -g OUTPUT_DIR="${PWD}/handbrakeOutput"
declare -g ASSUME_YES=false



echo "first using default values" 
echo "so now TARGET_DIR is: $TARGET_DIR"
echo "so now OUTPUT_DIR is: $OUTPUT_DIR"

[[ -e "${TARGET_DIR}" ]]  || echo "TARGET_DIR apparently doesn't exist"
[[ -e "${OUTPUT_DIR}" ]]  || echo "OUTPUT_DIR apparently doesn't exist"

declare -i total_seconds=0  #total time for the whole compressions process 
declare -a extList=( mp4 mkv mov avi m4v )  #all video extensions searched for (case insensitive) 
declare -a arr_videos=()


function main () {
  saved_IFS="$IFS";  IFS=' ''    ''
'
  _initialize "$@"
  _make_input_list
  _compress_all
  _final_summary

  IFS="$saved_IFS"

}

function _initialize () { 




  if [[$# -eq 2 ]];  then     
    [[ $# -ge 1 ]] && echo "got the 1st argument of: $1 " && TARGET_DIR=$1  
    [[ $# -ge 2 ]] && echo "got the 2nd argument of: $2 " && OUTPUT_DIR=$2  
  
  else  
    ## now parsing args  
    while [[ $# -gt 0 ]]; do
      case $1 in
        -t|-T|--target)
          TARGET_DIR="$2"
          shift # past this argument $1
          shift # past this value $2  ; for 2 part args to move on to the next pair
          ;;
        -o|-O|--output)
          OUTPUT_DIR=("$2"); shift; shift
          ;;
        -y|-Y|--yes|--YES|--assume-yes)
          ASSUME_YES=true; shift
          ;;
        -h|-H|--help)
          _correct_usage; shift; 
          exit 0
          ;;
        *)
          _correct_usage; shift # past argument
          ;;
      esac
    done
  fi
  
  echo "so now TARGET_DIR is: $TARGET_DIR"
  echo "so now OUTPUT_DIR is: $OUTPUT_DIR"

  [[ -e "${TARGET_DIR}" ]]  || echo "TARGET_DIR apparently doesn't exist"
  [[ -e "${OUTPUT_DIR}" ]]  || echo "OUTPUT_DIR apparently doesn't exist"





 
  #declare -g VIDEO_LIST_FILENAME="${TARGET_DIR}/videofileslist.txt" 
  declare -g LOG_FILENAME="/media/bradbao/bradbak/phoneBackup/logs/handbrake_batch.$(date +'%Y-%m-%d').log" 
  declare -g txt_grn_lit='\e[0;92m' # bright Green  for prompts
  declare -g txt_ylw_lit='\e[0;93m' # bright Yellow  for warnings 
  declare -g txt_cyn_lit='\e[0;96m' # bright Cyan  for summaries 
  declare -g txt_pur_lit='\e[0;95m' # bright Purple  for main video compression
  declare -g txt_non='\e[0m'        # back to default for most basic text 
  declare -g should_delete=false 

  echo "" | tee -a  "${LOG_FILENAME}"
  echo "the log filename is ${LOG_FILENAME}"  
  
  # shellcheck disable=SC2015
  [[ -d "${TARGET_DIR}"  ]] && cd "${TARGET_DIR}" || { echo -e "${txt_ylw_lit}ERROR: cant access ${TARGET_DIR} " ;  exit 1; }
  date  | tee -a  "${LOG_FILENAME}"
  echo -e "\n\n Now starting a new batch" | tee -a  "${LOG_FILENAME}"
  echo -e "The Target Dir is \n" "${TARGET_DIR}" | tee -a  "${LOG_FILENAME}"
 #  echo -e "Current video list filename being used is: \n${VIDEO_LIST_FILENAME}" | tee -a  "${LOG_FILENAME}"
  
 ##

  ## checks working directory for output folder 
  [[ -d "${OUTPUT_DIR}" ]] && echo -e "\nThe directory ${OUTPUT_DIR} is accessible" || mkdir --parents --verbose "${OUTPUT_DIR}"
  echo ""
  
  echo "did even more work  now... "
  echo "so now TARGET_DIR is: $TARGET_DIR"
  echo "so now OUTPUT_DIR is: $OUTPUT_DIR"
   

}


function _correct_usage () { 
  echo -e "if only 2 args are present it will be assumed to be target_dir and output_dir"   
  echo -e "a more full correct usage example:" 
  echo -e "handbrake_batch  --target '~/target/src/directory' \
   --output '~/target/export/directory' \
   --log '~/target/log_filename.log' \
   --yes " 
  echo -e "-y, --yes, --assume-yes  makes it non-interactive "
  echo -e "so will automaticaly start the compression and delete the source file after successful compression "
  echo -e "\nyou can also use short flags such as -t -o -l -y respectivly "
  echo -e "finally you can use a config file located here by default: \n${CONFIG_FILE} "  
    
} #end correct usage



function _make_input_list () {
  ## now checking target dir for each file extensions one by one
  cd "${TARGET_DIR}"  ||  echo -e "${txt_ylw_lit}ERROR: cant access ${TARGET_DIR} "
  declare -a found_vids=()
  for ext in "${extList[@]}"; do 
    echo  "Now checking target directory for extension: $ext"
    #this will only give relative path to  target dir 
    # this will search with find and add to arr videos.
   # did it this way to avoid issues of spaces and stuff   
    while IFS=  read -r -d $'\0'; do
      arr_videos+=("$REPLY")
     #  echo "single video found=$REPLY" 
    done < <(find .  -maxdepth 1 -iname "*.${ext}" -print0)

  done   #checking each file extension

  declare -i total_input_bytes=0
  declare -i size=0
  declare -i count_ready_vids=0

  for line  in "${arr_videos[@]}" ;  do 
    size=$(wc --bytes <"$line")
    total_input_bytes+="$size" 
   
    FULL_INPUT_PATH="${line%/*}" #everything before final slash 
    FILE_NAME="${line##*/}"  #get name only    everything after final slash 
    FILE_NO_EXTENSION="${FILE_NAME%.*}"
   #    FILE_EXT="${FILE_NAME##*.}"
    FULL_OUTPUT_TARGET="${OUTPUT_DIR}/${FILE_NO_EXTENSION}.720p.mp4"
    
   #    echo "FULL_INPUT_PATH=$FULL_INPUT_PATH"   
   #    echo "FILE_NAME=$FILE_NAME"   
   #    echo "FILE_NO_EXTENSION=$FILE_NO_EXTENSION" 
   #    echo "FULL_OUTPUT_TARGET=$FULL_OUTPUT_TARGET" 

    ##if it's already been compressed then note it here' 
    if [[ -f "${FULL_OUTPUT_TARGET}" ]]; then 
      echo -e "${txt_ylw_lit} $(numfmt --to=iec "$size")  $FILE_NAME ALREADY COMPRESSED  ${txt_non}" 
    else 
      echo -e "${txt_pur_lit} $(numfmt --to=iec "$size")  $FILE_NAME ready......... ${txt_non}"
      count_ready_vids+=1
    fi 
  done

  echo -e "${txt_non}"
  ##   reports
  echo -e "Total number of videos: ${#arr_videos[@]}" | tee -a  "${LOG_FILENAME}"
  echo -e "Total number of new videos not yet compressed: ${count_ready_vids}" | tee -a  "${LOG_FILENAME}"
  echo -e "Total size of all input videos: $(numfmt --to=iec "$total_input_bytes")"  | tee -a  "${LOG_FILENAME}"
  echo ""
  
  [[ ${count_ready_vids} == 0 ]] \
    && echo -e "${txt_ylw_lit}No videos found to compress.  So nothing more to be done. \nNow exiting ${txt_non}" \
    && exit 0
}


function _compress_all () {


  ## prompt to continue 
  echo -e "${txt_grn_lit}"   
  [[ "$(read -e -p "Do you want to continue with batch handbrake of these vids? (y/N) "; \
      echo "$REPLY")" == [Yy]* ]]  \
    || exit 0 
  [[ "$(read -e -p "Do you want to DELETE the original after successful compression? (y/N) "; \
      echo "$REPLY")" == [Yy]* ]]  \
    && should_delete=true || should_delete=false
    
  echo -e "\n${txt_non}Great! Now continuing batch \n"
  
  
  echo -e "${txt_pur_lit}"
  ## make it happen 
  for i in "${arr_videos[@]}" ; do
    echo -e "\nNow sending the following for Handbrake compression $i"  | tee -a  "${LOG_FILENAME}"
    date  | tee -a  "${LOG_FILENAME}"
    SECONDS=0  
    _compress_vid "$i"   
    echo -e "time to complete this video: $(( SECONDS/60 )) m $(( SECONDS%60 )) s" | tee -a  "${LOG_FILENAME}"
    [[ ${should_delete} == true ]]  && rm -v "$i" | tee -a  "${LOG_FILENAME}"
    
    total_seconds+=$SECONDS
        
  done
}
## Private compression function 
function _compress_vid () {   ##expects one arg $1
  local IFS=
  local line="$1" 
  local FULL_INPUT_PATH="${line%/*}" #everything before final slash 
  local FILE_NAME="${line##*/}"  #get name only  everything after final slash 
  local FILE_NO_EXTENSION="${FILE_NAME%.*}"
  local FILE_EXT="${FILE_NAME##*.}"
  local FULL_OUTPUT_TARGET="${OUTPUT_DIR}/${FILE_NO_EXTENSION}.720p.${FILE_EXT}"
  #echo  handbrake function input "$1"   
  echo -e "${txt_pur_lit}"  
  echo  "Full input path ${FULL_INPUT_PATH}"  
  echo  "Now compressing file ${FILE_NAME}"
  echo  "output target:  ${FULL_OUTPUT_TARGET}"
  echo -e " \n\n\n"
  
  #check if  exists already  "${FULL_INPUT_PATH}/${OUTPUT_DIR}/${FILE_NO_EXTENSION}.720p.mp4"

  if [[ -f "${FULL_OUTPUT_TARGET}" ]]; then 
    echo -e "${txt_ylw_lit}${FILE_NAME} already compressed. So skipping for now. " | tee -a  "${LOG_FILENAME}" 
  else 
    echo -e "${txt_pur_lit}"
    HandBrakeCLI -i "${line}" -o "${FULL_OUTPUT_TARGET}"  \
       --preset "Fast 720p30" --align-av --all-audio --aencoder copy:aac  \
       --encoder x264  --two-pass --turbo -q 20 --vfr   --optimize 
  fi
  echo -e "${txt_non}"  
}

function  _final_summary () {
  ## final summary 
  echo -e "${txt_cyn_lit}" 
  echo -e "\nDone compressing all videos!!" | tee -a  "${LOG_FILENAME}"
  echo -e "Total videos : "${#arr_videos[@]}  | tee -a  "${LOG_FILENAME}"
  echo -e "\nTotal size of all input videos: $(numfmt --to=iec "$total_input_bytes") "  | tee -a  "${LOG_FILENAME}"
  echo -e "\nTotal time to complete compression of all videos: " $(( total_seconds/60 )) "m " $(( total_seconds%60 )) "s" | tee -a  "${LOG_FILENAME}"
#  echo -e "The original input list is here:\n"  | tee -a  "${LOG_FILENAME}"
#  cat videofileslist.txt | tee -a  "${LOG_FILENAME}"
  echo -e "\nThe output directory now contains the following compressed vids:\n" | tee -a  "${LOG_FILENAME}"
  #find "${OUTPUT_DIR}"  -iname "*.mp4" | tee -a  "${LOG_FILENAME}"
  ls -lh --almost-all "${OUTPUT_DIR}"  | tee -a  "${LOG_FILENAME}"
  
  echo -e "${txt_non}" 
  echo -e "\n\nCheers" | tee -a  "${LOG_FILENAME}"
}


main "$@"
exit 0 


 #TARGET_DIR=$(echo "${PWD}" | sed 's/ /\\ /g')
  
#[[ "$(read -e -p "Do you want to DELETE the original? (y/N) "; echo "$REPLY")" == [Yy]* ]]  && should_delete=true || should_delete=false




