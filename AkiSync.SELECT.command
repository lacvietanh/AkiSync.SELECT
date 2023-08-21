#!/bin/bash
# Script Author: Lac Viet Anh
# Version: 2023.08.21-10:57
# AkiWorkflow.com

CL_RS='\033[0m'   # Reset
CL_0='\033[0;30m' # Black
CL_R='\033[0;31m' # Red
CL_G='\033[0;32m' # Green
CL_Y='\033[0;33m' # Yellow
CL_B='\033[0;34m' # Blue
CL_P='\033[0;35m' # Purple
CL_C='\033[0;36m' # Cyan
CL_W='\033[0;37m' # White

#check AkiWorkflow Partition:
diskutil info /Volumes/AkiWorkflow >/dev/null
if [ $? != 0 ]; then
    echo -e "${CL_R}AkiWorkflow Partition not found! ${CL_RS}"
    exit 1
fi
#test --si (Monterey+ support "du --si" for counting base10 instead of base2)
du -sh --si ~/.AWF >/dev/null
[ $? -eq 0 ] && _si=" --si " || _si=""

# Declare var and set default var:
declare akiUser akiPass mountName syncName m source dest
mountName="AkiWF_1TB"
dest=/Volumes/AkiWorkflow/Library/AudioLibrary/

menu() {
    clear
    echo "Select Sync:"
    echo "  a: Whole AudioLibrary"
    echo "  1: Kontakt 1"
    echo "  2: Kontakt 2"
    echo "  3: Nexus3Library"
    echo "  4: SD3 Library"
    echo "  s: STEAM Folder"
    echo "  p: pkgs"
    echo "  e: Exit"
}
ask() {
    if [ -z $m ]; then
        menu
        read -p "You select: " m
    fi
    case $m in
    a)
        syncName=AudioLibrary
        source="/Volumes/$mountName/Library/AudioLibrary"
        ;;
    1)
        syncName=Kontakt1
        source="/Volumes/$mountName/Library/AudioLibrary/Kontakt"
        dest=/Volumes/AkiWorkflow/Library/AudioLibrary/Kontakt/
        ;;
    2)
        syncName=Kontakt2
        mountName="AkiWF_2TB"
        source="/Volumes/$mountName/Kontakt"
        dest=/Volumes/AkiWorkflow/Library/AudioLibrary/Kontakt/
        ;;
    3)
        syncName=Nexus3
        #Build Nexus3 Library Structure:
        source="/Volumes/$mountName/Library/AudioLibrary/NexusLibrary"
        dest=/Volumes/AkiWorkflow/Library/AudioLibrary/
        rsync -havu --exclude 'Samples/*' "${source}" "${dest}"
        source="/Volumes/$mountName/Library/AudioLibrary/NexusLibrary/Samples"
        dest=/Volumes/AkiWorkflow/Library/AudioLibrary/NexusLibrary/Samples/
        ;;
    4)
        syncName=SD3
        mountName="AkiWF_2TB"
        source="/Volumes/$mountName/SD3"
        rsync -Phavu "${source}" "${dest}"
        exit 0
        ;;
    s)
        syncName=STEAM
        source="/Volumes/$mountName/Library/AudioLibrary/STEAM"
        dest=/Volumes/AkiWorkflow/Library/AudioLibrary/STEAM/
        ;;
    p)
        syncName=pkgs
        source="/Volumes/$mountName/Installer/pkgs"
        dest=/Volumes/AkiWorkflow/Installer/pkgs/
        mkdir -p $dest
        rsync -Phavu "${source}" "${dest}"
        exit 0
        ;;
    e) exit 0 ;;
    *)
        echo "Invalid option"
        unset m
        sleep 1
        clear
        ask
        ;;
    esac
}

askUserPass() {
    local Ask tmp strcmd
    mkdir -p ~/.AWF
    touch ~/.AWF/u
    touch ~/.AWF/p
    strcmd=" giving up after 10 default button 2"
    #username
    tmp=$(cat ~/.AWF/u)
    echo "Load from saved username: [$tmp]"
    akiUser=$(osascript -e \
        'display dialog "AkiCloud username:" default answer "'"$tmp"'" '"$strcmd"'' \
        -e 'set T to text returned of the result' -e 'return T')
    [ ! -z "$akiUser" ] && echo "$akiUser" >~/.AWF/u || echo "Empty Username!"
    #password
    tmp=$(cat ~/.AWF/p)
    echo "Load from saved password: [$tmp]"
    akiPass=$(osascript -e \
        'display dialog "AkiCloud password:" with hidden answer default answer "'"$tmp"'" '"$strcmd"'' \
        -e 'set T to text returned of the result' -e 'return T')
    if [ ! -z "$akiPass" ]; then
        echo "$akiPass" >~/.AWF/p
    else
        echo "Empty Password! Exit AkiSync..."
        exit 1
    fi
}
killRunningSync() {
    IFS=$'\n' read -d '' -r -a JOBS <$listPID
    for JobLine in "${JOBS[@]}"; do
        _name=$(echo "$JobLine" | cut -d "|" -f 2)
        _pid=$(echo "$JobLine" | cut -d "|" -f 1)
        ps -p $_pid >/dev/null
        if [ $? == 0 ]; then
            kill -9 $_pid
            echo -e "Killed failue sync process of:\t[${_name}]"
        fi
    done
}
mount() {
    local str
    str="afp://$akiUser:$akiPass@cloud.akivn.net/$mountName"
    if [ ! -d "/Volumes/$mountName" ]; then
        echo "Volume $mountName not mounted yet! mounting as user [$akiUser] ..."
        osascript -e 'mount volume "'$str'"'
    fi
}
check() {
    ping -c1 -t10 cloud.akivn.net >/dev/null
    if [ "$?" != 0 ]; then
        disTime=$(date +%T)
        echo "disconnected at $disTime" >>~/.AWF/disconnect.txt
        mount
        if [ $SyncRunning == 1 ]; then
            killRunningSync
            SyncRunning=0
            sync
        fi
    fi
}
sync() {
    askUserPass
    mount
    cd $source
    local c=1 #count
    for dir in *; do
        if [ -d "$dir" ]; then
            ((c = c + 1))
            rsync -haur "${source}/${dir}" "$dest" &
            mkdir -pv "${dest}/${dir}"
            echo -e "$!|$dir" >>"${listPID}"
        fi
    done
    printf "\e[8;$c;75t"
}
fsize() {
    osascript -e \
        'set f to POSIX file "'"$1"'" as alias' -e \
        'tell application "Finder"' -e 'set s to size of f' -e \
        'end tell' -e 'return s'
}
monitor() {
    IFS=$'\n' read -d '' -r -a JOBS <$listPID
    echo "" >$LogFile #init empty
    for JobLine in "${JOBS[@]}"; do
        _name=$(echo "$JobLine" | cut -d "|" -f 2)
        _pid=$(echo "$JobLine" | cut -d "|" -f 1)
        _size=$(du -sh "${dest}/${_name}" | cut -f 1 -d "/" | xargs)
        # _size=$(fsize "${dest}/${_name}")
        ps -p $_pid >/dev/null
        [ $? == 0 ] && _status="${CL_C}Syncing.." || _status="${CL_G}Finished!"
        echo -e "${_status}\t${_size}\t${_name}${CL_RS}" >>$LogFile
    done
    cat $LogFile
}
ask
LogFile="/tmp/monitor-$syncName.log"
listPID="/tmp/listSyncPID-$syncName.txt"
echo "" >"${listPID}" #init empty
SyncRunning=0
mkdir -p ~/.AWF

sync &
sumSyncPID=$!
SyncRunning=1
echo ParentSync PID: $!
echo SyncName: $syncName
echo MountName: $MountName
while sleep 4; do
    check
    monitor
    sleep 1
done
