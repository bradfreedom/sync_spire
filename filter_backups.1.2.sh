#!/usr/bin/env bash 

version="1.2"
echo -e "\nThis is the script \nfilter_backups version ${version}\n"
echo -e "this script will take in filename patterns from blacklist, config file, or args "
echo -e "and recursivly search within the target directory for these files"
echo -e "then dump/move them to an output directory"
echo -e "this script can handle searching for sha256 hashes" 
  
declare -a arr_blacklists=()   #array of filenames of blacklists that are provided by the user as arguments 
declare -a arr_blacklist_patterns=()   #array of all blacklist regex patterns pulled from those blacklists  
declare -a arr_files_found=()   #array of full path of all files found matching the blacklists patterns 
declare -a arr_blacklist_hashes=()   #array of all sha256 hashes found in file 

#set defaults ... note these will be overridden if there is a config file: 
CONFIG_FILE="/home/bradbao/Documents/scripts/filter_backups.conf"
#CONFIG_FILE=""
TARGET_DIR='.'  
OUTPUT_DIR='./filter_dump_dir'
#BLACKLIST1='/media/bradbao/bradbak/phoneBackup/blacklists/file_blacklist.txt'
BLACKLIST1=""
#FILTER_LOG="./filter_backups.$(date +'%Y-%m-%d').log"     #general log used for all steps, debugging, dates, and details. 
FILTER_LOG=""     #general log used for all steps, debugging, dates, and details. 
ASSUME_YES="no"
source  "${CONFIG_FILE}" 2>/dev/null 1>/dev/null



main () {  

  _initialize "$@"
 
  _iterate_blacklists

  [[ ${#arr_blacklist_patterns[@]} -gt 0 ]] && _search_target_dir
  [[ ${#arr_blacklist_hashes[@]} -gt 0 ]] && _search_hashes_target_dir
  [[ ${#arr_files_found[@]} -gt 0 ]] &&  _move_files  
  _exit_script
} #end main 

function _correct_usage () {

  echo -e "${txt_cyn_lit}" 
  echo -e "correct usage example:" 
  echo -e "filter_backups \\  \n--target '~/target/src/directory'  \
   \\ \n--blacklist '~/lists/BLACKLIST1.txt' \\ \n--pattern 'example.*' \\ \n--output '~/target/dump/directory' \
   \\ \n--log '~/target/log_filename.log' \\ \n--config '~/target/filter_backups.conf \\ \n--assume-yes"
  echo -e "\nyou can also use short flags such as -t -b -p -o -l -c -y respectivly "
  echo -e "--log can be a specific file or a directory"
  echo -e "you can also specify multiple blacklists such as" 
  echo -e "$ filter_backups -b list1.txt -b list2.txt ...\n "
  echo -e "or multiple patterns such as" 
  echo -e "$ filter_backups -p '*.txt' -p '*.mp3' ...\n "
  echo -e "finally you can optionally use a config file located here by default: \n${CONFIG_FILE} "  
  echo -e "${txt_non}"   
} #end correct usage

function _initialize () {
   
  [[ $# -eq 0 ]] && echo -e "\nNo args given so using defaults and/or config file"
  while [[ $# -gt 0 ]]; do
    case $1 in
      -t|-T|--target)
        TARGET_DIR="$2"
        shift # past this argument $1
        shift # past this value $2  ; for 2 part args to move on to the next pair
        ;;
      -b|-B|--blacklist)
        arr_blacklists+=("$2"); shift; shift
        ;;
      -p|-P|--pattern)
        pattern=$2
        arr_blacklist_patterns+=("$pattern")
        [[ ${#pattern} -ge 64 ]] && first_64=${pattern:0:64}
        if [[ $first_64 =~ ^[a-fA-F0-9]{64}$ ]]; then
          arr_blacklist_hashes+=("${first_64}")
        fi
        shift; shift
        ;;
      -o|-O|--output)
        OUTPUT_DIR=("$2"); shift; shift
        ;;
      -l|-L|--log)
        FILTER_LOG=("$2"); 
        [[ -d FILTER_LOG ]] && FILTER_LOG="${FILTER_LOG}/filter_backups.$(date +'%Y-%m-%d').log"
        shift; shift
        ;;
      -c|-C|--config)
        CONFIG_FILE=("$2"); 
        user_given_config="yes"; shift; shift
        ;;
      -y|-Y|--yes|--assume-yes)
        ASSUME_YES="yes"; shift
        ;;  
      -h|-H|--help)
        _correct_usage; shift
        exit 0
        ;;
      *)
        _correct_usage; shift # past argument
        ;;
    esac
  done
  # echo -e "${txt_red_lit}   size and contents of arr_blacklists is ${#arr_blacklists[@]} : ${arr_blacklists[@]}${txt_non}"
  
  ## source/load config file 
  ## notice the silencing of 2 stderr and 1 stdout to prevent any crazy config stuff 
  [[ -r  "${CONFIG_FILE}" &&  ${user_given_config} == "yes" ]] \
    && source  "${CONFIG_FILE}" 2>/dev/null 1>/dev/null \
    && echo -e "\njust loaded config file: ${CONFIG_FILE}" \
    || echo -e "\ncould not find the config file. \nInstead will rely on CLI arguments"
  
  #if  blacklists  is empty  then populate with default  list  
  if [[ ${#arr_blacklists[@]} -eq 0 && "${BLACKLIST1}" != "" ]]; then
    arr_blacklists+=("$BLACKLIST1") 
    echo "no blacklists provided so using default: " 
    echo "$BLACKLIST1"
  fi

  [[ "${FILTER_LOG}" == "" ]] &&  FILTER_LOG="${TARGET_DIR}/filter_backups.$(date +'%Y-%m-%d').log" 

  #initialize the filter log. this is for all steps, debugging, dates, and details. 
  #This script will ADD to the log only (tee -a ) not delete previous logs
  #FILTER_LOG="${TARGET_DIR}/filter_log.$(date +'%Y-%m-%d').log"   
  touch "${FILTER_LOG}"
  echo -e "\nRunning filter_backups script" | tee -a "${FILTER_LOG}"    
  date | tee -a "${FILTER_LOG}"    
    
  echo "Target DIR to search     = ${TARGET_DIR}"
  echo "Output DIR to dump files = ${OUTPUT_DIR}"
  echo "all blacklists           = ${arr_blacklists[@]}"
  echo "# of blacklists          = ${#arr_blacklists[@]}"
  echo "Filtering log used       = ${FILTER_LOG}"
  echo ""
  #sanity checks
  #check target and output dirs ... otherwise major errors later in the script of course. 
  [[ -d "${TARGET_DIR}" ]] && echo -e "Target Directory is readable \n${TARGET_DIR}" \
    || ( echo "ERROR: Target Directory is not readable" ; _exit_script )
  [[ "${TARGET_DIR}" == "${OUTPUT_DIR}" ]] \
    &&  echo "ERROR. both input and output directories are the same!" && _exit_script
  [[ -e "${OUTPUT_DIR}" ]] || mkdir -v "${OUTPUT_DIR}"
  

} ##end of initialize

function _iterate_blacklists () {
  ## part 1 - go through each of the black lists 
  ## add each item therewithin to the array arr_blacklist_patterns 
  echo -e "${txt_grn_lit}"
  
  #first pre-exisiting blacklist patterns if any
  [[ ${#arr_blacklist_patterns[@]} -gt 0 ]] \
    && echo -e "patterns from args or config files: "
  for pattern in  "${arr_blacklist_patterns[@]}"; do
      echo -e "$pattern"
  done 

  #now iterating blacklists
  for list in "${arr_blacklists[@]}"; do
    [[ ! -r $list ]] && echo "this blacklist is unreadable: $list" && continue;  # skip ahead to next itteration in the for loop/  next list
     
    echo -e "\nNow parsing through blacklist: $list \n"   | tee -a "${FILTER_LOG}"   
    echo -e "Now adding the following blacklist patterns from that list:" 
    while read -r line; do
      
      [[ ${#line} -le 2 ]] && continue    #skip to the next item  
      first_64=""
      #remove the leading and trailing spaces 
      trimmed_line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//') 
      # remove  '  and " 
      stripped_line=$(echo "$trimmed_line" | tr -d "'\"") 
       
      #check for a sha256 hash line     
      [[ ${#stripped_line} -ge 64 ]] && first_64=${stripped_line:0:64} 
      if [[ $first_64 =~ ^[a-fA-F0-9]{64}$ ]]; then 
        echo "Valid SHA-256 hash was found: ${first_64}." 
        arr_blacklist_hashes+=("${first_64}") 
        #send along the remainder of the line 
        remaining_string="${stripped_line:64}" 
        trimmed_line=$(echo "$remaining_string" | sed 's/^[ \t]*//;s/[ \t]*$//') 
        stripped_line=$(echo "$trimmed_line" | tr -d "'\"") 
      fi

      [[ ${#stripped_line} -lt 3 ]] && continue  
      arr_blacklist_patterns+=("${stripped_line}")
      echo "${stripped_line}"
       
    done < "$list"   #while loop - each blacklist one by one    
  
  done   #outer  for loop  going through ALL blacklists
  
  echo -e "\nCombined blacklist pattern count = ${#arr_blacklist_patterns[@]}"
  #echo "${arr_blacklist_patterns[@]}"

  ## part 2 - now create megastring to be used in a future FIND command
  # the goal is for the final string to look like this example: 
  #   -iname '*.py' -or -iname '*.html'  ....

  echo -e "\nThis script uses 'find . -iname' and NOT -iwholename' "
  echo -e "thus matches base file names only ... NOT path matches"
  mega_search_string=""
  fd_mega_search_string=""
  for pattern in "${arr_blacklist_patterns[@]}"; do
    [[ ${#mega_search_string} -gt 1 ]] && mega_search_string+=" -or "  
    mega_search_string+=" -iname '${pattern}' "   
    fd_mega_search_string+=" -g '${pattern}' "   #-g  --glob  
  done
  
  [[ ${#mega_search_string} -eq 0 ]] \
    && echo -e "Search string is empty! Nothing to search for. \nThus now exiting" \
    && _exit_script
} ## end of part 1 and 2 _iterate_blacklists 

function _search_hashes_target_dir () {
  [[ ${#arr_blacklist_hashes[@]} -eq 0 ]] && return

  echo -e "\n${txt_grn_lit}"
  echo "Target DIR to search      = ${TARGET_DIR}"
  echo "Output DIR to dump files  = ${OUTPUT_DIR}"
  echo "# of hashes to search for = ${#arr_blacklist_hashes[@]}"
  echo "Filtering log used        = ${FILTER_LOG}"

  echo -e "\nFirst we will check the size and count the files in your Target DIR"
  echo -e "if you have >10,000 files or >1TB then this may take a while... "

  target_search_size=$(du -ch "${TARGET_DIR}" | tail -n1)
  
  if [[ -e $(which fdfind) ]]; then   
    echo -e "You have fdfind installed which is faster than normal find."
    echo -e "Now using fdfind."

    target_file_count=$(fdfind -t f "${TARGET_DIR}" | wc -l )
    search_prg="$(which fdfind)"
    find_flags="--type f"
    
  else 
    echo -e "fdfind (which is faster) is not installed so using normal find."
    echo -e "most linux systems you can easily install it: \nsudo apt-get install fd-find"
    target_file_count=$(find "${TARGET_DIR}" -type f  | wc -l )
    search_prg="$(which find)"
    find_flags="-type f"

  fi

  echo -e "Total files to search :  ${target_file_count} "
  echo -e "Total size to search  :  ${target_search_size} "

  echo -e "for perspective 1TB can take from 30 minutes up to 3 hours to hash "
  echo -e 
  read -r -e -p "Would you like to continue the search and start comparing hashes? (y/N) " 
  [[ "${REPLY}" == [Yy]* ]] && echo -e "ok let's do this...\n" || return
  
  #this outer while loop looks at every single file in the target dir. 
  while IFS= read -r file_name; do
      #filter out 1 char file_names and junk
      [[ ${#file_name} -le 2 ]] && continue    #this moves to the next iteration of the loop   
      
      hash_of_file=$(sha256sum ${file_name})
      first_64=${hash_of_file:0:64} 
      meta_data_hash=$(mediainfo ${file_name} | sha256sum)
 
      for blacklist_hash in ${arr_blacklist_hashes[@]}; do 
        if [[ ${blacklist_hash} == ${first_64} || ${blacklist_hash} == ${meta_data_hash} ]]; then 
          echo -e "found a matching hash! ${file_name} \n${hash_of_file}"
          arr_files_found+=("$file_name")
          bytes_size=$(wc --bytes <"$file_name")
          total_input_bytes+=${bytes_size} 
          file_size=$(numfmt --to=iec "${bytes_size}")   
          print_format="%+6s : %s\n"  #this is to leverage the printf power of formating
          printf "${print_format}" "${file_size}" "$file_name" 
          break
        fi
      done  

  done < <(printf "%s \"%s\" %s  " "${search_prg}" "${TARGET_DIR}" "${find_flags}"  | bash )

###done with recent edit on aug 10  here  


}





function _search_target_dir () {
  ## part 3 search the target directory 
  #this will ONLY search for the files and add them to arr_files_found 
  
  [[ ${#mega_search_string} -eq 0 ]] && echo -e "${txt_red_lit}\nno patterns to search" && return 
  SECONDS=0
  echo -e "${txt_blu_lit}"
  declare -i total_input_bytes=0
  declare -i bytes_size

  #need to exclude the output_dir  from the search. 
  #path must be relative to to the target dir 
  realpath_output_dir=$(realpath --relative-to="${TARGET_DIR}" "${OUTPUT_DIR}" )
  search_command="fdfind --hidden --type file --print0 \
    ${fd_mega_search_string}  . "
 #   --exclude '${realpath_output_dir}' \
  #[[ ! -e $(which fdfind) ]] \
  #  && search_command=$(printf "find \"%s\" -type f %s " "${TARGET_DIR}" "${mega_search_string}") \
  #  && echo "no fdfind  on your system so using standard 'find'"   
  
  #due to issues with fdfind  just using fallback here of find. 
  search_command=$(printf "find \"%s\" -type f %s " "${TARGET_DIR}" "${mega_search_string}") 

  cd "${TARGET_DIR}"
  #echo -e "using the following search command: \n$search_command"

  echo -e "\n\nNow searching the following target directory : \n${TARGET_DIR}\n"
  echo -e "(this may take a while depending on size and I/O)"
  echo -e "these are the files found (if any):" 

  # due to complexities with variable expansion we use the "printf find pipe to bash"  method  
  # resulting found files will be piped  to while loop then appended to "arr_files_found"
  while IFS= read -r file_name; do
    #filter out 1 char file_names and junk
    [[ ${#file_name} -le 2 ]] && continue    #this moves to the next iteration of the loop 
    #filter out the dump directory itself. 
    [[ "${file_name}" == *"${OUTPUT_DIR}"* ]] && continue


    arr_files_found+=("$file_name")
    bytes_size=$(wc --bytes <"$file_name")
    total_input_bytes+=${bytes_size} 
    file_size=$(numfmt --to=iec "${bytes_size}")   
    print_format="%+6s : %s\n"  #this is to leverage the printf power of formating
    printf "${print_format}" "Size" "Filename" 
    printf "${print_format}" "${file_size}" "$file_name" 

  done < <(printf "%s" "${search_command}"  | bash )

#  done < <(printf "find \"%s\" -type f %s " "${TARGET_DIR}" "${mega_search_string}"  | bash )

  [[ ${#arr_files_found[@]} -lt 1 ]] \
    &&  echo -e "ZERO matches. \nEither bad blacklist or target dir is already filtered'\n" \
    &&  _exit_script
  
  echo -e "In Target Dir matches found : ${#arr_files_found[@]}"
  echo -e "Size of all files together  : $(numfmt --to=iec ${total_input_bytes})"
  printf "\nTime to search target dir for blacklisted file patterns: "  
  printf "$(( SECONDS/60 )) m $(( SECONDS%60 )) s \n"
  

} # end parts 2 and 3 _search_target_dir

function _move_files () {
  ## part 4 - make the move permenantly  
  echo -e "${txt_ylw_lit}\n\n"

  #sanity check
  [[ ${#arr_files_found[@]} -lt 1 ]] && echo -e "\nThere are NO FILES to move." && _exit_script 
  
  echo -e "TARGET DIR                  = ${TARGET_DIR}"
  echo -e "OUTPUT DIR (to dump files)  = ${OUTPUT_DIR}"
  echo -e "Assume YES on all files?    = $ASSUME_YES"
  if [[ ${ASSUME_YES} == "no" ]]; then 
    echo -e "\nDo you want to continue the filter and MOVE/DUMP "
    echo -e "these ${#arr_files_found[@]} files from the TARGET DIR -> OUTPUT DIR?"	
    read -r -e -p "This action can NOT be undone!  (y/N) " 
    [[ "${REPLY}" == [Yy]* ]]  \
      && echo -e "ok let's do this...\n"  \
      || _exit_script
  fi 
  echo "\nNow continuing the dump of blacklisted files into dump directory"  | tee -a "${FILTER_LOG}"    
  SECONDS=0
  
  #the following will MOVE mv the file to  the output DIR - "dump" the blacklisted file
  #thus removing from the target dir every time
  #-force overwriting anything that already exists in the DEST directory  
  #use this VERY carefully!  
  declare -i move_count=0
  declare -i total_input_bytes=0

  for filename in "${arr_files_found[@]}"; do
   
    [[ ${#filename} -le 3 ]] && continue  
   
    echo -e "${txt_non}${filename} ${txt_ylw_lit}"
    [[ ${ASSUME_YES} == "no" ]] && read -e -p "Do you want to move this file to the Dump dir? (y/N/always) "
    [[ "${REPLY}" == [Aa]* ]] && ASSUME_YES='yes' 

    file_size=$(wc --bytes <"$filename") 
    if [[ "${REPLY}" == [Yy]* || ${ASSUME_YES} == 'yes' ]]; then
      mv --verbose --force "${filename}" --target-directory="${OUTPUT_DIR}" | tee -a "${FILTER_LOG}" \
        && total_input_bytes+=$file_size \
        && ((move_count++))
    fi  #inner if 

  done
 
  ##  cleanup  and summarize 
  echo -e "\nBlacklisted files removed/filtered : ${move_count}" 
  echo -e "Combined size of all files removed : $(numfmt --to=iec ${total_input_bytes})"

  echo -e "Time to complete : " $(( SECONDS/60 )) "m " $(( SECONDS%60 )) "s \n" | tee -a "${FILTER_LOG}"
  echo -e "View this log for details: ${FILTER_LOG} "  
} # end of part 4 _move_files

function _exit_script() {
  echo -e "${txt_non}now exiting the script:  filter_backups ${version} \nCheers! "
  exit 0
  #this "set -e"  will cause the whole script to abort 
  #if a non-zero exit code happens such as the builtin 'false'
  set -e ; false 
}  # end of more graceful _exit_script



txt_red_lit='\e[0;91m' # bright Red
txt_grn_lit='\e[0;92m' # bright Green
txt_ylw_lit='\e[0;93m' # bright Yellow
txt_blu_lit='\e[0;94m' # bright Blue
txt_pur_lit='\e[0;95m' # bright Purple
txt_cyn_lit='\e[0;96m' # bright Cyan
txt_non='\e[0m'    # back to default


main "$@"

exit 0 

