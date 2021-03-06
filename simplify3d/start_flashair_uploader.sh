#!/bin/bash 

# Usage
# Add this line in the Simplify3D "Additional terminal commands for post processing" field.
# <path to this file> [output_filepath]
#
# Doesn't not worth with Simplify3D versions prior to 3.1.0. Those versions require
# the older version of this script which accept the gcode file path as the command
# line flag and wait for the completion of the x3g generation. These problems were
# fixed in Simplify3D 3.1.0.

# NOTE: working directory is established by the caller. If need a specific
# directory, make sure to set it here.

# TODO: include file name/size in the notification
# TODO: include upload time in completion notification.
# TODO: include useful info in error notifications (e.g. log file).
# TODO: tie notification clicks to log file
# TODO: replace literals with consts
# TODO: include instructions for setting up the Flashair card.

# Change banner time. This is persistent and affects all banners.
# TODO: does this require system reboot to take affect? If so, mention in comments.
# TODO: is there a way to extend the banner time just for this script?
defaults write com.apple.notificationcenterui bannerTime 60 

notifier="/Applications/terminal-notifier-1.6.3/terminal-notifier.app/Contents/MacOS/terminal-notifier"

# Network address of the Flashair SD card. Customize as needed.
flashair_ip="192.168.0.8"

# Called upon script starts. Accepts command line args.
function init {
  # Process command line args.
  x3g_path="$1"
  x3g_name=$(basename "${x3g_path}")
  
  echo "x3g_path: [${x3g_path}]"
  echo "x3g_name: [${x3g_name}]"
}


# Max OSX specific display popup notification. 
# Required installation of terminal-notifier.
function notification {
  echo $1
  echo $2
  if [ "$last_notification" != "$1#$2" ]
  then
    last_notification="$1#$2"
    ${notifier} -group 'x3g_uploader' -title 'Flashair Uploader' -subtitle "$1" -message "$2"
  fi
}

# Call just after involing a command. 
# arg1: command name/description.
function check_last_cmd() {
  status="$?"
  if [ "$status" -ne "0" ]; then
    notification "FAILED" "While $1"
    exit 1
  fi
}

# Return the current date/time as a FAT32 timestamp (a string with
# 8 hex characters)
function fat32_timestamp {
  # Get current date
  local date=$(date "+%-y,%-m,%-d,%-H,%-M,%-S")

  # Split to tokens
  # TODO: make tokens variable local.
  IFS=',' read -ra tokens <<< "$date"
  local YY="${tokens[0]}"
  local MM="${tokens[1]}"
  local DD="${tokens[2]}"
  local hh="${tokens[3]}"
  local mm="${tokens[4]}"
  local ss="${tokens[5]}"

  # Compute timestamp (8 hex chars)
  local fat32_date=$((DD + 32*MM + 512*(YY+20)))
  local fat32_time=$((ss/2 + 32*mm + 2048*hh))
  printf "%04x%04x" $fat32_date $fat32_time
}

function main {
  init $*

  local fat32_timestamp=$(fat32_timestamp)

  # Start a short timer to make sure the Connecting message is displayed
  # for at least this minimal time.
  sleep 1.5 &
  timer_job_id="$!"

  # This notification should be replaced quickly with the Uploading
  # notification below. If not, it indicates that the Flashair card
  # is not available. Hence the 'Connecting' title.
  # The actual operation is setting the filetimestamp since the
  # FlashAir doesn't have and independent date/time source of its own.
  #
  notification "CONNECTING" "File: ${x3g_name}"
  curl -v \
    --connect-timeout 5 \
    ${flashair_ip}/upload.cgi?FTIME=0x${fat32_timestamp}

  check_last_cmd "connecting"
 
  # Wait if needed to have the Connecting message displayed long enough
  # for the user to notice.
  wait $timer_job_id

  size=`du -h  $x3g_path | cut -f1`
  check_last_cmd "getting size"

  notification "UPLOADING" "File: ${x3g_name}  ${size}"
  curl -v \
    --connect-timeout 5 \
    -F "userid=1" \
    -F "filecomment=This is a 3D file" \
    -F "image=@${x3g_path}" \
    ${flashair_ip}/upload.cgi


  check_last_cmd "uploading"
  
  notification "DONE" "File: ${x3g_name}  ${size}"
}

main $* &>/tmp/flashair_uploader_log &
echo "Loader started in in background..."
