[[ -z "${VERBOSE}" ]] && export VERBOSE=false # Support tests + Disable execution messages in STDOUT
[[ -z "${DRYRUN}" ]] && export DRYRUN=false # Support tests + Disable execution, just STDOUT

# Arrays should return with newlines so we can do something like "${output##*$'\n'}" to get the last line
IFS=$'\n'

if [[ $- == *i* ]]; then # Disable if the shell isn't interactive (avoids: tput: No value for $TERM and no -T specified)
  export COLOR_NC=$(tput sgr0) # No Color
  export COLOR_RED=$(tput setaf 1)
  export COLOR_GREEN=$(tput setaf 2)
  export COLOR_YELLOW=$(tput setaf 3)
  export COLOR_BLUE=$(tput setaf 4)
  export COLOR_MAGENTA=$(tput setaf 5)
  export COLOR_CYAN=$(tput setaf 6)
  export COLOR_WHITE=$(tput setaf 7)
fi

function execute() {
  ( [[ ! -z "${VERBOSE}" ]] && $VERBOSE ) && echo " - Executing: $@"
  ( [[ ! -z "${DRYRUN}" ]] && $DRYRUN ) || "$@"
}


function execute-always() {
  ( [[ ! -z "${VERBOSE}" ]] && $VERBOSE ) && echo " - Executing: $@"
  "$@"
}

function ensure-git-clone() {
  if [ ! -d "${REPO_ROOT}/.git" ]; then
    echo "This build script only works with sources cloned from git"
    echo "For example, you can clone a new eos directory with: git clone https://github.com/EOSIO/eos"
    exit 1
  fi
}

function ensure-submodules-up-to-date() {
  if [[ $DRYRUN == false ]] && [[ $(execute git submodule status --recursive | grep -c "^[+\-]") -gt 0 ]]; then
    echo "git submodules are not up to date."
    echo "Please run the command 'git submodule update --init --recursive'."
    exit 1
  fi
}

function ensure-sudo() {
  if [[ $DRYRUN == false ]] && [[ -z $( command -v sudo ) ]]; then echo "You must have sudo installed to run the build scripts!" && exit 1; fi
}

function previous-install-prompt() {
  if [[ -d $EOSIO_INSTALL_DIR ]]; then
    echo "EOSIO has already been installed into ${EOSIO_INSTALL_DIR}... It's suggested that you eosio_uninstall.bash before re-running this script."
    while true; do
      [[ $NONINTERACTIVE == false ]] && printf "${COLOR_YELLOW}Do you wish to proceed anyway? (y/n)${COLOR_NC}" && read -p " " PROCEED
      echo ""
      case $PROCEED in
        "" ) echo "What would you like to do?";;
        0 | true | [Yy]* ) break;;
        1 | false | [Nn]* ) exit;;
        * ) echo "Please type 'y' for yes or 'n' for no.";;
      esac
	  done
  fi
}

function set_system_vars() {
    if [[ $ARCH == "Darwin" ]]; then
        export OS_VER=$(sw_vers -productVersion)
        export OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
        export OS_MIN=$(echo "${OS_VER}" | cut -d'.' -f2)
        export OS_PATCH=$(echo "${OS_VER}" | cut -d'.' -f3)
        export MEM_GIG=$(bc <<< "($(sysctl -in hw.memsize) / 1024000000)")
        export DISK_INSTALL=$(df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 || cut -d' ' -f1)
        export blksize=$(df . | head -1 | awk '{print $2}' | cut -d- -f1)
        export gbfactor=$(( 1073741824 / blksize ))
        export total_blks=$(df . | tail -1 | awk '{print $2}')
        export avail_blks=$(df . | tail -1 | awk '{print $4}')
        export DISK_TOTAL=$((total_blks / gbfactor ))
        export DISK_AVAIL=$((avail_blks / gbfactor ))
    else
        export DISK_INSTALL=$( df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 )
        export DISK_TOTAL_KB=$( df . | tail -1 | awk '{print $2}' )
        export DISK_AVAIL_KB=$( df . | tail -1 | awk '{print $4}' )
        export MEM_GIG=$(( ( ( $(cat /proc/meminfo | grep MemTotal | awk '{print $2}') / 1000 ) / 1000 ) ))
        export DISK_TOTAL=$(( DISK_TOTAL_KB / 1048576 ))
        export DISK_AVAIL=$(( DISK_AVAIL_KB / 1048576 ))
    fi
    export JOBS=$(( MEM_GIG > CPU_CORES ? CPU_CORES : MEM_GIG ))
}

function install-package() {
  ORIGINAL_DRYRUN=$DRYRUN
  [[ ! -z $2 ]] && DRYRUN=false
  if [[ $ARCH == "Linux" ]]; then
    ( [[ $NAME =~ "Amazon Linux" ]] || [[ $NAME == "CentOS Linux" ]] ) && execute $( [[ $CURRENT_USER == "root" ]] || echo /usr/bin/sudo -E ) ${YUM} install -y $1 || true
    [[ $NAME =~ "Ubuntu" ]] && execute $( [[ $CURRENT_USER == "root" ]] || echo /usr/bin/sudo -E ) apt-get update && ( execute $( [[ $CURRENT_USER == "root" ]] || echo /usr/bin/sudo -E ) $APTGET install -y $1 || true )
  fi
  DRYRUN=$ORIGINAL_DRYRUN
  true # Required; Weird behavior without it
}

function uninstall-package() {
  ORIGINAL_DRYRUN=$DRYRUN
  [[ ! -z $2 ]] && DRYRUN=false
  if [[ $ARCH == "Linux" ]]; then
    ( [[ $NAME =~ "Amazon Linux" ]] || [[ $NAME == "CentOS Linux" ]] ) && ( execute $( [[ $CURRENT_USER == "root" ]] || echo /usr/bin/sudo -E ) ${YUM} remove -y $1 || true )
    [[ $NAME =~ "Ubuntu" ]] && ( execute $( [[ $CURRENT_USER == "root" ]] || echo /usr/bin/sudo -E ) $APTGET remove -y $1 || true )
  fi
  DRYRUN=$ORIGINAL_DRYRUN
  true
}