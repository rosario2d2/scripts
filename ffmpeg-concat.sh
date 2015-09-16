#!/bin/bash

# ffmpeg-concat
# Copyright (C) 2015 Rosario Prestigiacomo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Arguments
BANNER=$1
DIRECTORY=${2%/}
NAME=$3

# Options defaults
SCALE="640x360"
FORMAT="mp4"
LOGLEVEL="info"
RESIZE=0
KEEP=0

# Usage dialog
read -r -d '' USAGE << EOM

ffmpeg-concat - Simple script to concat a banner to the beginning and the end of every video in a dir
This program is free software: GPL v3 or any later version
Copyright (C) 2015 Rosario Prestigiacomo

Usage:
ffmpeg-concat <banner> <video-directory> <output-filename> [options]

Options:
-r    resize - don't resize the banner, assuming it's maching the same resolution and aspect ratio of the video to concat
-k    keep - keep the scaled banner in the video dir (default is to delete it)
-s    scale - set the resolution (default is 640x360)
-f    format - select the output format (default mp4)
-l    loglevel - log level for ffmpeg (default info)
-h    help - show this dialog

EOM

# Check the arguments
if [ $# -lt 3 ]; then
    echo -e "$USAGE"
    exit 1
fi

# Check the banner is a valid file
if [ ! -f "$BANNER" ]; then
    echo "The banner - $BANNER - doesn't exists or is a directory"
    exit 1
fi

# Check the destination dir exists
if [ ! -d "$DIRECTORY" ]; then
    echo "Video directory - $DIRECTORY - not found"
    exit 1
fi

# Getopts options
shift 3
while getopts ':hrks:f:l:' OPTION; do
    case "$OPTION" in
        h) echo "$USAGE"
            exit 1
            ;;
        r) RESIZE=1
            ;;
        k) KEEP=1
            ;;
        s) SCALE=$OPTARG
            ;;
        f) FORMAT=$OPTARG
            ;;
        l) LOGLEVEL=$OPTARG
            ;;
        :) printf "Missing argument for -%s\n" "$OPTARG" >&2
           echo "$USAGE" >&2
           exit 1
           ;;
        \?) printf "Illegal option: -%s\n" "$OPTARG" >&2
           echo "$USAGE" >&2
           exit 1
           ;;
    esac
done

# Colors
g=$'\e[32m'
y=$'\e[33m'
r=$'\e[31m'
c=$'\e[0m'

# Errors and Skipped files
ERRORS[0]=$r"Errors:"$c
ERRNUM=1
SKIPPED[0]=$y"Skipped:"$c
SKIPNUM=1

# Resize the banner to the desired resolution or keep it as it is
if [ $RESIZE -eq 1 ]; then
    RESBAN=$BANNER
else
    ffmpeg -i "$BANNER" -loglevel "$LOGLEVEL" -strict -2 -vf scale="$SCALE",setsar=1:1 -c:v libx264 -preset fast -profile:v main -crf 20 "$DIRECTORY"/"$BANNER"-banner-resize."$FORMAT"
    if [ $? -eq 0 ]; then
        RESBAN="$DIRECTORY"/"$BANNER"-banner-resize."$FORMAT"
    else
        # Log banner resize error
        ERRORS[ERRNUM]="Cannot resize - $BANNER - banner."
        ((ERRNUM++))
    fi
fi

# For every file in the directory
for VIDEO in "$DIRECTORY"/*
do
    # Check if the file is a video(doesn't work with mkv)
    if file -i "$VIDEO" | grep -q video ; then
        # Don't execute if the file is the banner or the script itself
        if [ "$VIDEO" != "$BANNER" ] && [ "$VIDEO" != "$RESBAN" ] && [ "$VIDEO" != "$0" ]; then
            # Resize video
            ffmpeg -i "$VIDEO" -loglevel "$LOGLEVEL" -strict -2 -vf scale="$SCALE",setsar=1:1 -c:v libx264 -preset fast -profile:v main -crf 20 "$VIDEO"-resize."$FORMAT"
            # In case of success
            if [ $? -eq 0 ]; then
                # Create the concat
                ffmpeg -i "$RESBAN" -i "$VIDEO"-resize."$FORMAT" -i "$RESBAN" -loglevel "$LOGLEVEL" -strict -2 -filter_complex "[0:0] [0:1] [1:0] [1:1] [2:0] concat=n=3:v=1:a=1 [v] [a]" -map "[v]" -map "[a]" "$VIDEO"-"$NAME"."$FORMAT"
                # If everithing was fine and dandy, clean and move on
                if [ $? -eq 0 ]; then
                    echo ""
                    echo "Cleaning - $VIDEO - resize temp file."
                    rm "$VIDEO"-resize."$FORMAT"
                else
                    # Log concatenate errors
                    ERRORS[ERRNUM]="Cannot concatenate - $VIDEO - video with banner."
                    ((ERRNUM++))
                fi
            else
                # Log resize errors
                ERRORS[ERRNUM]="Cannot resize - $VIDEO - video."
                ((ERRNUM++))
            fi
        fi
    else
        # Log skipped files
        SKIPPED[SKIPNUM]="$VIDEO - this file is not a video, skipping."
        ((SKIPNUM++))
    fi
done

# Delete the resized banner unless -k option is selected
if [ $KEEP -eq 0 ] && [ $RESIZE -eq 0 ]; then
    rm "$RESBAN"
fi

echo -e "\n"

# Show skipped files and dirs if any
if [ "$SKIPNUM" != 1 ]; then
    printf '%s\n' "${SKIPPED[@]}" '%s\n'
fi

# Show errors if any
if [ "$ERRNUM" != 1 ]; then
    printf '%s\n' "${ERRORS[@]}" '%s\n'
fi

# Final report
echo $g"Final report: "$c"$((SKIPNUM -1 )) skipped and $((ERRNUM -1)) errors."
