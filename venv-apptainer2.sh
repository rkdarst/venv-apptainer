# This file must be sourced and then used via the `vea` shell alias.

# Basic image definitions (image source and local file name)
declare -g -A VENVA_IMAGES
VENVA_IMAGES[pip]="docker://python:3.14-trixie"
VENVA_IMAGES[pip_file]="python-3.14.sif"
VENVA_IMAGES[conda]="docker://condaforge/miniforge3:26.9.4-0"
VENVA_IMAGES[conda_file]="miniforge-26.sif"
VENVA_IMAGES[uv]="docker://astral/uv:0.13-debian-slim"
VENVA_IMAGES[uv_file]="uv-0.13.sif"
VENVA_IMAGES[moat]="docker://ghcr.io/aaltorse/moat:v0.3.2"
VENVA_IMAGES[moat_file]="moat-0.3.2.sif"

# Accept an existing value of VENVA_IMG_DIR if it exists.  Otherwise,
# store images in ~/sys/ if it exists.  Otherwise in the location of
# this script.
if [ -n "$VENVA_IMG_DIR" ] ; then
    true
elif [ -d ~/sys/ ] ; then
    VENVA_IMG_DIR="$HOME"/sys/
else
    VENVA_IMG_DIR="$(realpath "$(dirname "${BASH_SOURCE:-${(%):-%x}}")")/"
fi

# Shell function.  This is made to be sourced in .bashrc to always be
# available.
function vea() {
    #set -x
    local BASE=venva                 # base path for env
    local PATH_IN=/venv-apptainer/   # mountd path in the container
    local -a BINDS                   # for zsh must make this an array
    local -a INSTALL_OPTS            # Holds the requested command line args for installation
    local -a BIN_DIRS                # Add programs from these paths to ./venva/bin/
    local -a BIN_EXECS               # Add these programs to ./venva/bin/
    local install_type               # what type of env do we make?
    local -a ORIG_ARGS
    ORIG_ARGS=("$@")

    # Parse command line arguments.
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "usage: vea [OPTS] [INSTALL_ARGS [...]]"
                echo
                echo "NOTE: [[--OPT [VALUE]] ...] must come before [INSTALL_ARGS] and "
                echo "--OPT and VALUE must be space, not '=', separated."
                echo
                echo "INSTALL_OPTS   If one argument: use this requirements file"
                echo "               (default: detect environment.yml and use conda, "
                echo "               then pip with pylock.toml or"
                echo "               requirements.txt in that order)"
                echo "               Multiple arguments: pass these arguments to pip/"
                echo "               conda/etc.  Default pip, use --conda for conda."
                echo "               Example: venva -r requirements.txt extra_package"
                echo "--img IMG.sif  Override apptainer image file"
                echo "--force        Force a rebuild.  Doesn't delete old files, only"
                echo "               deletes a possible squashfs. Otherwise, installs"
                echo "               on top of old files.  Beware of problems."
                echo "--base         Install at this path instead of venva."
                echo "               Default: venva"
                echo "--no-squash    Don't compact to a squashfs filesystem.  Allows"
                echo "               updating/editing later"
                echo "--pip          Install file with pip"
                echo "--conda        Install file with conda"
                echo "--uv           Install file with uv.  Alpha."
                echo "--moat         Set up moat for AI agents.  Alpha."
                echo "--bind BIND    Extra binds (may be given multiple times)"
                echo "               Same format as apptainer.  Must be absolute path."
                echo "--bind-ro BIND Like above but expanded to BIND:BIND:ro"
                echo "-e DIR         Automatic 'pip install -e' support.  Bind-ro mount"
                echo "               and -e DIR for editable install.  You also need"
                echo "               -r requirements.txt since it won't be automatic with"
                echo "               this option."
                echo "--verbose      Run with set -x"
                shift
                return
                ;;
            --verbose)    trap 'set +x' RETURN ; set -x ;      shift   ;;
            --img)        local IMG="$2";
                          if [ ! -e "$IMG" ] ; then echo "not present: $IMG" ; return 1 ; fi ;
                                                               shift 2 ;;
            -f|--force)   local VENVA_FORCE=true ;             shift   ;;
            --base)       BASE="$2" ;                          shift 2 ;;
            --no-squash)  local NO_SQUASH=true ;               shift   ;;
            --bind)             BINDS+=(--bind="$2") ;         shift 2 ;;
            --bind-ro)          BINDS+=(--bind="$2":"$2":ro) ; shift 2 ;;
            -e)                 BINDS+=(--bind="$2":"$2":ro) ;
                                INSTALL_OPTS+=(-e "$2") ;      shift 2 ;;
            --pip)        install_type=pip ;                   shift   ;;
            --conda)      install_type=conda ;                 shift   ;;
            --uv)         install_type=uv ;                    shift   ;;
            --moat)       install_type=moat ;                  shift   ;;
            *)            INSTALL_OPTS+=("$@") ;               break   ;;
        esac
    done

    # If the environment seems to already exist, so activate it and return.
    # Delete the $BASE (./venva/) directory to re-create.
    if test -z "$VENVA_FORCE" -a -e "$BASE" ; then
        #PATH="$PWD/$BASE/bin/":"$PATH"
        #VIRTUAL_ENV="$BASE"
        source "$BASE"/activate
        return
    fi

    # Detect what our mode should be (pip, conda, which requirements
    # file).  Priority to --pip or --conda, then environment.yml,
    # pylock.toml, requirements.txt in that order.
    if   [ "$install_type" = pip ] ; then
        if [ "${#INSTALL_OPTS[@]}" -eq 0 ] ; then
            if test -e requirements.txt ; then
                INSTALL_OPTS+=(-r requirements.txt)
            elif test -e pylock.toml ; then
                 INSTALL_OPTS+=(-r pylock.toml)
            fi
        fi
    elif [ "$install_type" = conda ] ; then
        test -z "$INSTALL_OPTS" && INSTALL_OPTS+=(-f environment.yml)
    elif [ "$install_type" = uv ] ; then
        test -z "$INSTALL_OPTS" && INSTALL_OPTS+=(sync)
    elif [ "$install_type" = moat ] ; then
        test -z "$INSTALL_OPTS" && INSTALL_OPTS+=(n/a)
    # One argument - requirements file
    elif [ "${#INSTALL_OPTS[@]}" -eq 1 ] ; then
        case "${INSTALL_OPTS[*]:0:1}" in
            *.txt|*.toml)
                install_type=pip
                INSTALL_OPTS=(-r "${INSTALL_OPTS[@]}")
            ;;
            *.yml)
                install_type=conda
                INSTALL_OPTS=(-f "${INSTALL_OPTS[@]}")
            ;;
        esac
    # Multi-arg options: install exactly with the args given
    elif [ "${#INSTALL_OPTS[@]}" -ne 0 ] ; then
        install_type=pip
    elif [ -e environment.yml ]  ; then install_type=conda ; INSTALL_OPTS+=(-f environment.yml)
    elif [ -e pylock.toml ]      ; then install_type=pip   ; INSTALL_OPTS+=(-r pylock.toml)
    elif [ -e requirements.txt ] ; then install_type=pip   ; INSTALL_OPTS+=(-r requirements.txt)
    fi
    # Warn if nothing was detected
    if [ -z "$INSTALL_OPTS" ] ; then
        echo "No requirements file auto-detected"
        return 1
    fi

    # Handle Pip vs Conda specialities.
    local install_command run_command
    local IMG IMG_SOURCE
    if [ "$install_type" = pip ] ; then
        # Get the image
        if test -z "$IMG" ; then
           IMG="${VENVA_IMG_DIR}/${VENVA_IMAGES[pip_file]}"
           IMG_SOURCE="${VENVA_IMAGES[pip]}"
        fi
        install_command='python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install "$@"'
        run_command='bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" [in-container] "$@"'
        mkdir -p "$HOME"/.cache/pip-apptainer
        BINDS+=("--bind=$HOME/.cache/pip-apptainer/:$HOME/.cache/pip")
        BIN_DIRS+=("$PATH_IN"/bin/)
        SQUASHFS_FILE=venv.squashfs
    elif [ "$install_type" = conda ] ; then
        if test -z "$IMG" ; then
           IMG="${VENVA_IMG_DIR}/${VENVA_IMAGES[conda_file]}"
           IMG_SOURCE="${VENVA_IMAGES[conda]}"
        fi
        install_command='conda env create --yes -p /venv-apptainer "$@"'
        run_command='bash -c "source activate /venv-apptainer ; \${@:-bash}" [in-container] "$@"'
        mkdir -p "$HOME"/.cache/conda-apptainer "$HOME"/.conda-apptainer/
        BINDS+=("--bind=$HOME/.cache/conda-apptainer/:$HOME/.cache/conda/")
        BINDS+=("--bind=$HOME/.conda-apptainer/:$HOME/.conda/")
        BIN_DIRS+=("$PATH_IN"/bin/)
        SQUASHFS_FILE=conda-env.squashfs
    elif [ "$install_type" = uv ] ; then
        if test -z "$IMG" ; then
           IMG="${VENVA_IMG_DIR}/${VENVA_IMAGES[uv_file]}"
           IMG_SOURCE="${VENVA_IMAGES[uv]}"
        fi
        install_command='export UV_PROJECT_ENVIRONMENT=/uv-apptainer/ ; uv venv /uv-apptainer/ ; source /uv-apptainer/bin/activate ; uv "$@"'
        run_command='bash -c "export UV_PROJECT_ENVIRONMENT=/uv-apptainer/ ; source /uv-apptainer/bin/activate ; \${@:-bash}" [in-container] "$@"'
        PATH_IN=/uv-apptainer/
        mkdir -p "$HOME"/.cache/uv-apptainer
        mkdir -p "$HOME"/.local/share/uv-apptainer
        BINDS+=("--bind=$HOME/.cache/uv-apptainer:$HOME/.cache/uv")
        BINDS+=("--bind=$HOME/.local/share/uv-apptainer:$HOME/.local/share/uv")
        BIN_DIRS+=("$PATH_IN"/bin/)
        BIN_DIRS+=('/usr/local/bin/')
        SQUASHFS_FILE=uv-env.squashfs
    elif [ "$install_type" = moat ] ; then
        if test -z "$IMG" ; then
           IMG="${VENVA_IMG_DIR}/${VENVA_IMAGES[moat_file]}"
           IMG_SOURCE="${VENVA_IMAGES[moat]}"
        fi
        install_command=true
        #run_command='bash -c "true ; \${@:-bash}" [in-container] "$@"'
        run_command='bash -c "export PATH=\$PATH:/opt/nvm/versions/node/v24.22.0/bin/ ; \${@:-bash}" [in-container] "$@"'
        local MOAT_HOME="$HOME/.moat/home/"
        mkdir -p "$MOAT_HOME"/"$(realpath "$PWD" --relative-to "$HOME")"
        BINDS+=("--bind=$MOAT_HOME:$HOME/")
        BINDS+=("--bind=$XDG_RUNTIME_DIR")
        BINDS+=("--bind=/dev/null:$XDG_RUNTIME_DIR/bus")
        BINDS+=("--bind=/run/dbus")
        BIN_DIRS+=("/usr/local/bin/")
        BIN_DIRS+=("/usr/share/code/bin/")
        BIN_DIRS+=("/usr/share/codium/bin/")
        BIN_DIRS+=("/opt/nvm/versions/node/v24.22.0/bin/")
        SQUASHFS_FILE=moat-env.squashfs
    else
        echo "No requirements file found (requirements.txt or environment.yml)"
        return 1
    fi

    # Pull the image if not yet pulled.  It is set above.
    if test ! -e "$IMG" ; then
        apptainer pull "${IMG}" "${IMG_SOURCE}"
        local ret=$?
        if [ $ret -ne 0 ] ; then
            echo "Failed pulling ${IMG_SOURCE} to ${IMG}"
            return 1
        fi
    fi

    # If force mode: delete the existing environment's squashfs.  This
    # may not work under other circumstances.
    if test -n "$VENVA_FORCE" -a -e "$BASE"/"$SQUASHFS_FILE" ; then
        echo "Deleting $BASE/$SQUASHFS_FILE"
        rm -v "$BASE"/"$SQUASHFS_FILE"
    fi

    # Print debugging info
    echo "Installing type=$install_type to base=${BASE} with ${INSTALL_OPTS[@]}"
    echo "Binds: ${BINDS[@]}"

    # Make the environment directories
    mkdir -p "$BASE"/venv
    mkdir -p "$BASE"/bin
    mkdir -p "$BASE"/tmp

    # Do the actual building
    apptainer exec \
              --cwd "$PWD" \
              --bind "$PWD:$PWD" \
              --bind="$BASE"/venv:"$PATH_IN" \
              "${BINDS[@]}" \
              --workdir="$BASE"/tmp \
              --contain --env LANG=C --env LC_ALL=C \
              "$IMG" \
              bash -c "$install_command" [install-container] "${INSTALL_OPTS[@]}"
    if [ $? -ne 0 ] ; then
        echo "Apptainer command failed"
        return 1
    fi

    # Note that this is \$BASE - $BASE gets interperted at the point
    # of execution of the ./venva/exec script, so that it is relocateable!
    # This is default without squashfs:
    local BIND_ENV="--bind=\"\$BASE/venv\":$PATH_IN"

    # Make it a squashfs, if mksquashfs is installed.
    if test -z "$NO_SQUASH" && type mksquashfs > /dev/null ; then
        mksquashfs "$BASE"/venv/ "$BASE/$SQUASHFS_FILE" -quiet
        BIND_ENV="--bind=\"\$BASE\"/${SQUASHFS_FILE}:${PATH_IN}:ro,image-src=/"
        rm -r "$BASE"/venv/
    fi

    # Install the `$BASE/exec` wrapper that includes all the options
    # we need to run within the container.  This wrapper also
    # activates the environments within the container, then runs
    # either a shell or the command given on the command line.
    # hard-coding bash not ideal but needs better than sh.
    echo '#!/bin/bash'                            >  "$BASE"/exec
    # $FUNCNAME doesn't work in zsh, but OK.
    echo '# Original arguments:'                  >> "$BASE"/exec
    echo '#  ' "$FUNCNAME" "${ORIG_ARGS[@]}"      >> "$BASE"/exec
    echo '# Computed install args:'               >> "$BASE"/exec
    echo '#  ' "${INSTALL_OPTS[@]}"               >> "$BASE"/exec
    echo                                          >> "$BASE"/exec
    echo 'BASE="$(dirname "$0")"'                 >> "$BASE"/exec
    echo "BINDS=($(printf '%q\n' "${BINDS[@]}"))" >> "$BASE"/exec
    echo "IMG=\"$IMG\""                           >> "$BASE"/exec
    echo                                          >> "$BASE"/exec
    echo apptainer exec                           $'\\\n   ' \
         --contain --env LANG=C --env LC_ALL=C    $'\\\n   ' \
         --bind '"$PWD:$PWD"'                     $'\\\n   ' \
         "$BIND_ENV"                              $'\\\n   ' \
         '"${BINDS[@]}"'                          $'\\\n   ' \
         --cwd '"$PWD"' '--workdir="$BASE"/tmp'   $'\\\n   ' \
         '"$IMG"'                                 $'\\\n   ' \
         "$run_command"                                      \
         >> "$BASE/exec"
    chmod a+x "$BASE"/exec

    # In $BASE/bin/, install wrappers for all programs within the
    # environment (/venv-apptainer/bin/ on the container).  These
    # transparently run the respective programs within the container.
    for BIN_DIR in "${BIN_DIRS[@]}" ; do
        for executable in $(./"$BASE"/exec ls "$BIN_DIR") ; do
            echo 'BASE="$(dirname "$0")/../"' > "$BASE"/bin/"$executable"
            echo '"$BASE"/exec' "$executable" '"$@"' >> "$BASE"/bin/"$executable"
            chmod a+x "$BASE"/bin/"$executable"
        done
    done

    # Create the activate script, which adds the venv to the path.
    # The ${BASH_SOURCE:-${(%):-%x}} construct allows something like
    # BASH_SOURCE on zsh, too.
    echo 'PATH="$(realpath "$(dirname "${BASH_SOURCE:-${(%):-%x}}")")"/bin/:"$PATH"' > "$BASE"/activate
    echo 'export VIRTUAL_ENV="$(basename "$(dirname ${BASH_SOURCE:-${(%):-%x}})")"' >> "$BASE"/activate

    # Activate the environment
    source "$BASE"/activate
    #set +x
}
