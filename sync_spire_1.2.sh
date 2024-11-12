#!/usr/bin/env bash 


echo "This is sync_spire version 1.2.1" 
## source/load config file 
## notice the silencing of 2> stderr and 1> stdout to prevent any crazy config file mishaps or code injections 
# shellcheck source="/etc/sync_spire.conf"
CONFIG_FILE="/etc/sync_spire.conf"   ##default for now. 
[[ -r  "${CONFIG_FILE}" ]] || CONFIG_FILE="./sync_spire.conf" 
if [[ -r  "${CONFIG_FILE}" ]] ; then
  source  "${CONFIG_FILE}" 2>/dev/null 1>/dev/null
  echo -e "${txt_non}Just loaded config file: ${CONFIG_FILE}" 
else 
  echo -e "${txt_red_lit}\nCould not find the config file 'sync_spire.conf' ${txt_non}" 
  exit 1  
fi 

declare NEW_TMP_DIR=""  #this is used in case default dirs are changed by user

main () {
  _initalize
  _promt_user
  
  ##when done 
  echo -e "${txt_cyn_lit}\n\nAll done \nHere is the destination directory:\n"
  echo -e "${DEST_DIR}"
  
  #ls -lh "${DEST_DIR}"
  echo -e "${txt_non}"
  exit 0
  
}

function _initalize() {

  echo -e "\a${WELCOME_ASCII_ART} ${txt_non}"  
  
  ## sanity check Destination directory
  
  if [[ -d $DEST_DIR ]]  && [[ -r $DEST_DIR  ]]; then 
    date | tee -a "${LOG_FILENAME}" 
    echo -e "Now using the following as the destination for backups: \n${DEST_DIR}" 
  else  
    echo -e "${txt_ylw}It seems $DEST_DIR is not accessible thus there is nothing more to do."
    _get_new_dir "${DEST_DIR}"
    DEST_DIR="${NEW_TMP_DIR}"
    echo -e "${txt_non}"
  fi  # end of DEST_DIR  sanity check 
  
  echo -e "full (phone) SRC directory as sourced from config file is the following:\n${PHONE_DIR}"
  ##sanity check Source Phone directory  
  cd "${PATH_TO_MTP_MOUNTS}" 
  if [[ -d $PHONE_DIR ]]  && [[ -r $PHONE_DIR  ]]; then 
    #echo -e "The source (phone) directory:\n${PHONE_DIR}"
    numOfDevices=1
  else  
    echo -e "${txt_ylw}It seems the default phone directory $PHONE_DIR is not accessible${txt_non}"
    echo -e "Now attempting to detect connected devices"
    ##detect first device in path only
    numOfDevices=0
    cd "${PATH_TO_MTP_MOUNTS}" 
    #best way to search for DIRS  ... silence of error messages (especially on empty directory)
    connected_device=($(ls -d */ 2>/dev/null))  
    [[ ${#connected_device[@]} -gt 0 ]] && numOfDevices=1
    echo "Number of devices connected is ${numOfDevices}"
    
    if [ $numOfDevices == 0 ]; then 
      echo -e "${txt_ylw}It looks like no devices are currently connected."
      echo -e "more specificially there is nothing mounted to the local folder /run/user/1000/gvfs/"
      echo -e "\nregardless...\n"
      read -e -p "Would you like to abort? (y/N) "
      [[ "${REPLY}" == [Yy]* ]] && echo "${txt_cyn_lit}cool.  now exiting... ${txt_non}" && exit 0
    elif [ $numOfDevices == 1 ]; then 
      BASE_MTP=${connected_device[0]}      
      echo -e "Starting a new run using the following mtp \n$BASE_MTP" | tee -a "${LOG_FILENAME}"       
    else 
      echo -e "seems there is more than 1 device connected."
      echo -e "For now this script is not able to run parallel transfers."
      echo -e "For now using $BASE_MTP as default"        
    fi

  fi # end of PHONE_DIR  sanity check 
  PHONE_DIR="${PATH_TO_MTP_MOUNTS}${BASE_MTP}"
  
  ## project dependency sanity checks 
  echo -e "${txt_cyn_lit}"

  prg_path=$(which exiv2) 
  if [[ -r $prg_path ]]; then 
    echo -e "using exiv2 at path: $prg_path " 
  else
    echo -e "${txt_ylw}exiv2 doesn't seem to be installed on your system " 
    echo -e "required to strip metadata from images" 
    echo -e "you can find it here: https://exiv2.org/download.html  ${txt_cyn_lit}" 
    has_exiv2=false
  fi 
  
  prg_path=$(which nconvert) 
  if [[ -r $prg_path ]]; then  
    echo -e "using nconvert at path: $prg_path " 
  else 
    echo -e "${txt_ylw}the CLI nconvert doesn't seem to be installed on your system " 
    echo -e "required to batch downsize images" 
    echo -e "you can find it here: https://www.xnview.com/en/nconvert/ ${txt_cyn_lit}" 
    has_nconvert=false
  fi
  
  prg_path=$(which rsync) 
  if [[ -r $prg_path ]]; then 
    echo -e "using rsync at path: $prg_path " 
  else 
    echo -e "${txt_ylw}Rsync doesn't seem to be installed on your system " 
    echo -e "required for syncing backups ${txt_cyn_lit}"
    echo -e "you can find it here:   https://rsync.samba.org/ ${txt_cyn_lit}" 
    has_rsync=false 
  fi    
  
  prg_path=$(which HandBrakeCLI) 
  if [[ -r $prg_path ]]; then 
    echo -e "using HandBrakeCLI at path: $prg_path " 
  else
    echo -e "${txt_ylw}HandBrakeCLI doesn't seem to be installed on your system "
    echo -e "required for batch compressing videos "
    echo -e "you can find it here: https://www.xnview.com/en/nconvert/ ${txt_cyn_lit}"
    has_rsync=false
  fi
  
  prg_path=$(which handbrake_batch) 
  if [[ -r $prg_path ]]; then 
    echo -e "using script 'handbrake_batch' at path: $prg_path " 
  else 
    echo -e "${txt_ylw}the handbrake_batch script was not found on your system "
    echo -e "required to batch compress videos ${txt_cyn_lit}" ; 
    has_handbrake_batch=false ;
  fi
         
  prg_path=$(which filter_backups) 
  if [[ -r $prg_path ]] ; then 
    echo -e "using script 'filter_backups' at path: $prg_path " 
  else 
     echo -e "${txt_ylw}the filter_backups script was not found on your system " 
     echo -e "required to filter phone and backups ${txt_cyn_lit}" 
     has_filter_backups=false 
  fi

  prg_path=$(which clean_filenames) 
  if [[ -r $prg_path ]]; then 
    echo -e "using script 'clean_filenames' at path: $prg_path " 
  else  
    echo -e "${txt_ylw}the clean_filenames script doesn't seem to be installed on your system " ;\
    echo -e "required to rename files and tidy names ${txt_cyn_lit}" 
    has_clean_filenames=false 
  fi

  echo -e "${txt_non}"  

}
#end of _initialize function

function _promt_user(){
 
  echo -e "${txt_grn_lit}"
  ## prompt to continue various sections
  [[ $numOfDevices == 1 ]] \
    && read -e -p  "Do you want to continue with backup of full device? (y/N) " \
    && [[ "${REPLY}" == [Yy]* ]]  && _backup_all

  echo -e "${txt_grn_lit}"
  read -e -p "Do you want to copy key files (jpg,mp4,kmz ...) from main backup to Key directories? (y/N) "
    [[ "${REPLY}" == [Yy]* ]]  && _move_key_files

  ## blacklist scans  ## note that filter_backups is an external standalone script 
  echo -e "${txt_grn_lit}"  
  read -e -p "Do you want to scan your BACKUPS for blacklisted files? (y/N) " 
  [[ "${REPLY}" == [Yy]* ]] \
    && filter_backups --target "${DEST_DIR}" --output "${FILTER_DUMP_DIR}" \
       --blacklist "${blacklist1}" --log "${LOG_FILENAME}"  

  echo -e "${txt_grn_lit}"
  read -e -p "Do you want to scan your PHONE for blacklisted files? (y/N) "
  [[ "${REPLY}" == [Yy]* ]] \
    && filter_backups --target "${PHONE_DIR}" --output "${FILTER_DUMP_DIR}" \
       --blacklist "${blacklist1}" --log "${LOG_FILENAME}"  
  
  
  ##compression of pictures and videos  
  echo -e "${txt_grn_lit}"
  read -e -p "Do you want to batch compress all pictures using NConvert? (y/N) "
  [[ "${REPLY}" == [Yy]* ]]  && _nconvert
  
  echo -e "${txt_grn_lit}"
  read -e -p "Do you want to strip some exif metatdata from compressed pics? (y/N) "
  [[ "${REPLY}" == [Yy]* ]]  && _stripexif
  

  echo -e "${txt_grn_lit}"
  read -e -p "Do you want to do view the list of all backed up VIDEOS ? (y/N) "
  [[ "${REPLY}" == [Yy]* ]]  \
    && echo -e "\n${txt_non}The Video folder contains the following:" \
    && ls -lh "${VIDEOS_DIR}"

  echo -e "${txt_grn_lit}" 
  
  read -e -p "Do you want to do a batch handbrake compression of all VIDEOS ? (y/N) "
  [[ "${REPLY}" == [Yy]* ]]  \
    && echo -e "${txt_pur_lit}" \
    && cd "${VIDEOS_DIR}" \
    && handbrake_batch "${VIDEOS_DIR}" "${COMPRESSED_VIDS_DIR}"

  echo -e "${txt_non}"

}

function _backup_all() {   ##expects no args
  local IFS=
  SECONDS=0  
  cd "${DEST_DIR}"
  echo -e "${txt_non}"
  #echo  "$PWD"  

  echo -e "\nNow starting a FULL backup."  | tee -a  "${LOG_FILENAME}"  
  date  | tee -a  "${LOG_FILENAME}"
  echo -e "\nThis will likely take a long time (5-10 minutes) so please be patient..."  
  echo -e "\nRsync will use the blacklists here: " | tee -a  "${LOG_FILENAME}"   
  echo -e "${blacklist1}" | tee -a  "${LOG_FILENAME}"   
  echo -e "${blacklist2}" | tee -a  "${LOG_FILENAME}"   
  echo -e "${blacklist3}" | tee -a  "${LOG_FILENAME}"    
  echo -e "\nAnd using this whitelist (please note the whitelist takes precedence): \n${whitelist1}\n" | tee -a  "${LOG_FILENAME}"   
  

  #here we assume there might be more than 1 directory on phone main mountpoint
  # such as :  Internal shared storage     SD card
  #we recurse each of them 1 by 1 

  cd "${PHONE_DIR}"
  subdirs=(*) 
  for subdir in "${subdirs[@]}" ;  do  
    cd "${PHONE_DIR}/${subdir}" 
    echo -e "\n${txt_non}Now checking the path  $PWD "
    echo -e "${txt_ylw_lit}"
    rsync -a  --mkpath  --debug=FILTER --verbose  --progress  --times  --human-readable \
      --ignore-existing  --stats --cvs-exclude  --preallocate  --min-size=1k \
      --include-from="${whitelist1}"  \
      --exclude-from="${blacklist1}"  \
      --exclude-from="${blacklist2}"  \
      --exclude-from="${blacklist3}"  \
      "." "${FULL_RAW_BACKUP_DEST_DIR}" | tee -a "${LOG_FILENAME}"   #src  #dest   
  done
  echo -e "${txt_non}"
  echo -e "\nA summary of the backup is stored on the log file ${LOG_FILENAME}\n"
  echo -e "Time to complete :  $(( SECONDS/60 )) m  $(( SECONDS%60 )) s \n" | tee -a  "${LOG_FILENAME}"
  echo -e "${txt_ylw_lit}"
  clean_filenames "${FULL_RAW_BACKUP_DEST_DIR}"

  echo -e "${txt_non}"
  echo -e "\n\nnow copying notes to the notes archive and appending the date"
  echo -e "Source = ${SRC_NOTES_DIR}"
  echo -e "Destination = ${NOTES_ARCHIVE} \n"
  current_date=$(date +%Y-%m-%d)
  echo -e "${txt_ylw_lit}"

  # find "-print0"  flag adds nulls to end of each item  
  # read  -d $'\0'  uses  null  as a delimiter  
  while IFS=  read -r -d $'\0'; do
    if [[ "${#REPLY}" -gt 3  ]] ; then 
      base_name=$(basename "$REPLY" .txt)     
      new_filename="${base_name}.${current_date}.txt"
      cp "$REPLY" --verbose --no-clobber "${NOTES_ARCHIVE}/${new_filename}" 
    fi
  done < <(find "${SRC_NOTES_DIR}" -iwholename "*/Notes/*.txt" -print0)
  echo -e "${txt_non}"

}

## Private function to backup key files 
function _move_key_files() {   ##expects no args
  echo -e "${txt_non}"
  echo -e "\nGreat!  \nFiles will be updated only and NOT overwritten" 
  echo -e "\nNow copying/duplicating key files from fullRAWphoneBackup to appropriate folder." | tee -a  "${LOG_FILENAME}"
  date | tee -a "${LOG_FILENAME}"
  #  echo -e "\nCopying from device:" >> "${LOG_FILENAME}"
   # echo "${BASE_MTP}" >> "${LOG_FILENAME}"
  RAW="${FULL_RAW_BACKUP_DEST_DIR}" 
  SECONDS=0
 
  echo -e "${txt_blu_lit}"
  echo -e "\nPictures\n" | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f \( -iname "202*.jpg" -o -iname "img*.jpg" \)  -type f -exec cp {} -v  --no-clobber \
    "${PICTURES_DIR}" \; | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f -iwholename  "*/Zalo/*" -exec cp {} -v --update --no-clobber \
    "${ZALO_DIR}" \; | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f -iname  "signal-*.jpg" -exec cp {} -v  --update --no-clobber \
    "${SIGNAL_DIR}" \; | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f -iname  "screen*" -exec cp {} -v  --update --no-clobber \
    "${SCREENSHOTS_DIR}" \; | tee -a  "${LOG_FILENAME}"
  clean_filenames "${PICTURES_DIR}"

  echo -e "${txt_pur_lit}"
  echo -e "\nVideos\n" | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f \( -iname "vid*" -o -iname "*.mp4" \) -exec cp {} -v  --update --no-clobber \
    "${VIDEOS_DIR}" \; | tee -a  "${LOG_FILENAME}"
  
  echo -e "${txt_cyn_lit}"
  echo -e "\nOSM and Open tracks \n" | tee -a  "${LOG_FILENAME}"
  find "$RAW" -type f \( -iname "*.kmz*" -iname "*.gpx*" \) -exec cp {} -v --update  --no-clobber \
    "${TRIP_RECORDINGS_DIR}" \; | tee -a "${LOG_FILENAME}"
  
  # now  copy back  from trip recordings  back  to  phone  

  read -e -p "Do you want to sync your old OSM data back up to your phone? (y/N) " 
  if [[ "${REPLY}" == [Yy]* ]] ; then 
    echo -e "\nNow syncing/uploading previous OSM data FROM backups TO phone \n" | tee -a  "${LOG_FILENAME}"   
    osm_tracks_dir="${PHONE_DIR}/SD card/Android/data/net.osmand.plus/files/tracks"
    [[ -r "${osm_tracks_dir}" ]] \
      ||  osm_tracks_dir="${PHONE_DIR}/Internal shared storage/Android/data/net.osmand.plus/files/tracks/rec/"
    [[ -d "${osm_tracks_dir}" ]] ||  mkdir --parents "${osm_tracks_dir}"
    find "${TRIP_RECORDINGS_DIR}" -type f -iname "*.gpx*" -exec cp {} -v  --update --no-clobber \
      "${osm_tracks_dir}"  \; | tee -a  "${LOG_FILENAME}"
  fi

  echo -e "${txt_grn}"
  echo -e "\nAudio Recordings\n" | tee -a  "${LOG_FILENAME}"
  find "$RAW" -iname "*.m4a" -exec cp {} -v  --no-clobber \
    "${AUDIO_RECORDINGS_DIR}" \; | tee -a  "${LOG_FILENAME}"
  #clean_filenames "${AUDIO_RECORDINGS_DIR}"
   
  echo -e "${txt_ylw_lit}"
  echo -e "\nNotes and Subs\n" | tee -a  "${LOG_FILENAME}"
  find "$RAW" -iwholename "*/Notes/*.txt" -exec cp {} -v  --update --no-clobber \
    "${NOTES_DIR}"   \; | tee -a  "${LOG_FILENAME}"
  
  
  #now copy notes from computer back up to the phone 
  find "${NOTES_DIR}"  -maxdepth 1 -iname "*.txt"  -exec cp {} -v --update --no-clobber \
    "${SRC_NOTES_DIR}"   \; | tee -a  "${LOG_FILENAME}"

  find "$RAW" -iname "newpipe-subscriptions-*" -exec cp {} -v  --no-clobber \
    "${SUBS_DIR}" \; | tee -a  "${LOG_FILENAME}"
   
  echo -e "${txt_non}"
  echo -e "\nDone copying key files from raw backup to key directories.\n" | tee -a  "${LOG_FILENAME}"
  echo -e "Time to complete : " $(( SECONDS/60 )) "m " $(( SECONDS%60 )) "s \n" | tee -a  "${LOG_FILENAME}"
  
  
}  ##  end of _move_key_files
 
## Private function compress all pictures using nconvert and put all results into dir compressedPics
function _nconvert() {   ##expects no args
  
  [[ -e $(which nconvert)  ]] || { echo -e "${txt_red_lit}ERROR: Missing NConvert!${txt_non}" ; return 1; }

  echo -e "${txt_blu_lit}"
  
  declare -i input_pic_count        #total input pics
  declare -i success_count=0        #pics newly compressed 
  declare -i pic_progress_count=0   #number of iterations performed so far 
  declare -a arr_input_pics=()      #array of input pictures from PICTURES_DIR
  declare -a arr_compressed_pics=() #array of pics filenames compressed with this funcion 
  destination_file=""               #used to create temp new file name for each picture    
  #input_pic_count=$( ls --almost-all "${PICTURES_DIR}" | wc -l )
  
  cd "${PICTURES_DIR}"

  # find "-print0"  flag adds nulls to end of each item  
  # read  -d $'\0'  uses  null  as a delimiter  
  while IFS=  read -r -d $'\0'; do
    if [[ "${#REPLY}" -gt 3  ]] ; then 
      filename_only="${REPLY##*/}"  #get name only everything after final slash 
      arr_input_pics+=("$filename_only")
    fi
  done < <(find "${PICTURES_DIR}" -maxdepth 1 -iname "*.jpg" -print0)
  
  input_pic_count="${#arr_input_pics[@]}"

  [[ -d  $COMPRESSED_PICS_DIR ]] || mkdir --parents  "${COMPRESSED_PICS_DIR}"
  echo -e "\nNow compressing the pictures and logging to: ${LOG_FILENAME}" | tee -a "${LOG_FILENAME}"
  echo -e "The the input files will come FROM directory: ${PICTURES_DIR}"
  echo -e "The compressed pics will go INTO directory: ${COMPRESSED_PICS_DIR}" 
  echo -e "The total number of input pictures is: ${input_pic_count}" | tee -a  "${LOG_FILENAME}"  
  echo -e "Note this will ONLY log and compress new pictures and ignore those previously compressed "  
  
  date | tee -a "${LOG_FILENAME}"

  SECONDS=0  
  for current_pic in "${arr_input_pics[@]}" ; do   
    destination_file="${COMPRESSED_PICS_DIR}/${current_pic/".jpg"/".c.jpg"}" ;
    if [[ -f "${destination_file}" ]]; then 
      #echo "${current_pic} was already compressed! " 
      pic_progress_count+=1  
      _progress_bar "${pic_progress_count}" "${input_pic_count}"
    else 
      #where the magic happens.  notice  stdout and stderr  is silenced because nconvert is far too verbose 
      nconvert -ratio -rtype lanczos  -resize longest 3000  \
        -o "${destination_file}"  "${PICTURES_DIR}/${current_pic}" 2>/dev/null 1>/dev/null
      
      arr_compressed_pics+=("${current_pic}")       
      #echo -e "nconvert just compressed image "${current_pic}  | tee -a  "${LOG_FILENAME}"
      success_count+=1
      pic_progress_count+=1  
      _progress_bar "${pic_progress_count}" "${input_pic_count}"
    fi 
  done
  echo -e "the following images were compressed by nconvert:\n"  | tee -a  "${LOG_FILENAME}"
  printf "%s\n" "${arr_compressed_pics[@]}"  | tee -a  "${LOG_FILENAME}"  

  local compressed_already=$(( input_pic_count - success_count )) 
  echo -e "\n ${compressed_already} / ${input_pic_count}  pictures were compressed already. "  
  echo "Time to compress the remaining ${success_count} pictures: " $(( SECONDS/60 )) "m " $(( SECONDS%60 )) "s" | tee -a  "${LOG_FILENAME}"
  
  echo "The total number of jpg files now in dir /compressedPics is: " | tee -a  "${LOG_FILENAME}"  
  
  find "${COMPRESSED_PICS_DIR}" -maxdepth 1 -iname "*.jpg"  | wc -l  | tee -a  "${LOG_FILENAME}" 
  #ls --almost-all "*.jpg" "${COMPRESSED_PICS_DIR}" | wc -l  | tee -a  "${LOG_FILENAME}"  
  echo -e "${txt_non}"
}


## Private function strip some exif data 
function _stripexif() {   ##expects no args
  [[ -e $(which exiv2)  ]] || { echo -e "${txt_red_lit}ERROR: Missing exiv2!${txt_non}" ; return 1; }

  echo -e "${txt_blu_lit}"
  
  local exiv_command=""
  declare -i input_pic_count   
  declare -i pic_progress_count=0
  declare -a arr_pics=()
  
  cd "${COMPRESSED_PICS_DIR}"
  echo -e "Now searching the following directory for JPG pics to strip: \n${COMPRESSED_PICS_DIR}"

  # "-print0"  flag adds nulls to end of each item  
  # -d $'\0'  uses  null  as a delimiter  
  while IFS=  read -r -d $'\0'; do
    arr_pics+=("$REPLY")
  done < <(find . -maxdepth 1 -iname "*.jpg"  -print0)
  
  input_pic_count=${#arr_pics[@]}
  date | tee -a "${LOG_FILENAME}"
  #create exif string thus build up the command 
  exiv_command="exiv2  "
  echo -e "now stripping out the following exif tags:" 
  for tag  in "${EXIF_TAGS[@]}" ; do  
     if [[ ${#tag} -gt 1 ]] ;  then    
        echo -e "$tag" 
        exiv_command="${exiv_command} --Modify \"del $tag\" "
     fi 
  done 

  echo -e "\nThe total number of JPG files in the compressed pics directory  is: ${input_pic_count}"  | tee -a "${LOG_FILENAME}"
  echo -e "now executing the following command on each pic: \n" | tee -a "${LOG_FILENAME}"
  echo -e "${txt_non}${exiv_command}" | tee -a "${LOG_FILENAME}"
  echo -e "${txt_blu_lit}\nworking..."
  SECONDS=0  

  for current_pic in "${arr_pics[@]}" ; do     
    pic_progress_count+=1
    [[ "${#current_pic}" -gt 2 ]] \
      && printf "%s %s  2>/dev/null 1>/dev/null" "${exiv_command}" "${current_pic}" | bash 
    #above command we need to silence all stderr and stdout 
    _progress_bar "${pic_progress_count}" "${input_pic_count}"
  done 

  echo "Total time to strip tags from all compressed pictures: " $(( SECONDS/60 )) "m " $(( SECONDS%60 )) "s" | tee -a "${LOG_FILENAME}" 

  echo -e "${txt_non}"
}


function _progress_bar () {
  declare -i progress=$1
  declare -i total=$2
  declare -i width=50   ##how wide is the bar displayed in terminal
  declare -i len_done
  declare -i len_not_done

  #sanity checks
  [[ progress -gt total ]] && progress=$total 
  [[ progress -lt 0 ]] && progress=0
  [[ total -le 0 ]] && total=1

  len_done=$(( width * progress / total))  #sortv as a percentage of the total width
  len_not_done=$(( width - len_done ))

  hashline=$(printf "%${len_done}s" "" | tr " " "#")
  dashline=$(printf "%${len_not_done}s" "" | tr " " "-")
  echo -ne "\r[${hashline}${dashline}] ${progress} / ${total} files "
  
}


function _get_new_dir () { 
  ## this will take in a default dir as an argument 
  ## result will be updated to  NEW_TMP_DIR
  
  local default_dir=$1
  while true; do 
    read -p "${txt_grn_lit}Do you want to use the default directory: $default_dir? (Y/n): " user_input
    if [[ "${user_input}" != [Nn]* ]] ; then 
      # Check if the new directory path is valid
      [[ -d $default_dir ]] \
        && { echo ${txt_non}"OK. Using default directory: $default_dir" && break; } \
        || echo "${txt_red_lit}Error: Directory does not exist or is not accessible." 
    else
      echo -e "${txt_non}Current Path is  $PWD"
      read -p "Enter the new directory path (relative or absolute): " new_dir
      # Check if the new directory path is valid
      [[ -d $new_dir ]] \
        && { cd $new_dir  && default_dir=$PWD \
        && echo "${txt_non}Using new directory: $default_dir" ; break; } \
        || echo "${txt_red_lit}Error: Directory does not exist or is not accessible."
    fi
  done 
  NEW_TMP_DIR="$default_dir"

}

function _exit_script() {
  echo -e "${txt_cyn_lit}now exiting the script gracefully "
  #this "set -e"  will cause the whole script to abort 
  #if a non-zero exit code happens such as the builtin 'false'
 

  echo -e "\n\nCheers\n\n ${txt_non}"
  set -e ; false 

}  # end of more graceful _exit_script

##finally call main  and exit  

main 

exit 0

