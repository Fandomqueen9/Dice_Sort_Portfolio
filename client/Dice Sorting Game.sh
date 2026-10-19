#!/bin/sh
printf '\033c\033]0;%s\a' Dice Sorting Game
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Dice Sorting Game.x86_64" "$@"
