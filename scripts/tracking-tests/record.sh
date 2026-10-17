#!/bin/zsh
# Records what speech recognition hears for each test recording, two at a time,
# by playing the audio file straight into a debug build of Offscript.
# Usage: record.sh [recording ...]   (default: every audio file in record-scripts/)
# Needs: a Debug build (APP), test-audio/<recording>.m4a and record-scripts/<recording>.txt.
D=${DATA:-$(cd "$(dirname $0)/../.." && pwd)/test-audio}
APP=${APP:-/tmp/offscript-dd/Build/Products/Debug/Offscript.app}
mkdir -p $D/recordings
names=(${@:-$(cd $D/record-scripts && ls *.txt | sed 's/\.txt$//')})

audio_for() {
  case $1 in
    bevel-full) echo $D/bevel-whoop.m4a ;;
    *) echo $D/$1.m4a ;;
  esac
}

record() {
  local name=$1 audio=$(audio_for $1)
  local seconds=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $audio | cut -d. -f1)
  rm -f $D/recordings/$name-heard.jsonl $D/recordings/$name-positions.csv
  open -n $APP --args --test-audio $audio --test-script $D/record-scripts/$name.txt \
    --test-results $D/recordings --test-hidden --test-quit
  # Wait for the results, or stop the run a minute past the audio's length
  for i in {1..$((seconds + 60))}; do
    sleep 1
    [[ -f $D/recordings/$name-heard.jsonl ]] && { sleep 3; echo "recorded $name $(date +%H:%M)"; return; }
  done
  pkill -f -- "--test-script $D/record-scripts/$name.txt"
  echo "timed out $name"
}

while (( ${#names} )); do
  record ${names[1]} &
  (( ${#names} > 1 )) && record ${names[2]} &
  wait
  names=(${names[3,-1]})
done
