# Store images in ~/sys/ if it exists.  Otherwise in the location of
# this script.  If these variables are already defined, do nothing.
# There is no built-in way to override images for only one venv (yet).
if [ -d ~/sys/ ] ; then
    : "${VENV_APPTAINER_IMAGE:=$HOME/sys/python-3.14.sif}"
    : "${CONDA_APPTAINER_IMAGE:=$HOME/sys/miniforge-26.sif}"
else
    # The crazy construct ${BASH_SOURCE:-${(%):-%x}} (also seen below)
    # is a way to emulate $BASH_SOURCE on zsh (and this form works for
    # both bash and zsh)
    : "${VENV_APPTAINER_IMAGE:=$(realpath \"$(dirname \\\"${BASH_SOURCE:-${(%):-%x}}\\\")/python-3.14.sif)\"}"
    : "${CONDA_APPTAINER_IMAGE:=$(realpath \"$(dirname \\\"${BASH_SOURCE:-${(%):-%x}}\\\")/miniforge-26.sif)\"}"

fi

# Shell function.  This is made to be sourced in .bashrc to always be
# available.
function vea() {
    #set -x
    local BASE=venva                 # base path for env
    local PATH_IN=/venv-apptainer/   # mountd path in the container
    local -a BINDS                   # for zsh must make this an array

    # Parse command line arguments.
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "usage: vea [INSTALL_OPTS [...]]"
                echo
                echo "INSTALL_OPTS   If one argument: use this requirements file"
                echo "               (default: detect environment.yml, pylock.toml,"
                echo "               requirements.txt in that order)"
                echo "               Multiple arguments: pass these arguments to pip/"
                echo "               conda/etc.  Default pip, use --conda for conda."
                echo "               Example: venva -r requirements.txt extra_package"
                echo "--img IMG.sif  Override apptainer image file"
                echo "--force        Force a rebuild.  Doesn't delete old files, only"
                echo "               deletes a possible squashfs. Otherwise, installs"
                echo "               on top of old files.  Beware of problems."
                echo "--no-squash    Don't compact to a squashfs filesystem.  Allows"
                echo "               updating/editing later"
                echo "--pip          Install file with pip"
                echo "--conda        Install file with conda"
                echo "--bind BIND    Extra binds (may be given multiple times)"
                echo "               Same format as apptainer.  Must be absolute path."
                echo "--bind-ro BIND Like above but expanded to BIND:BIND:ro"
                echo "--verbose      Run with set -x"
                shift
                return
                ;;
            --verbose)    trap 'set +x' RETURN ; set -x ;      shift   ;;
            --img)        local IMG="$2";                      shift 2 ;;
            -f|--force)   local VENVA_FORCE=true ;             shift   ;;
            --no-squash)  local NO_SQUASH=true ;               shift   ;;
            --bind)             BINDS+=(--bind="$2") ;         shift 2 ;;
            --bind-ro)          BINDS+=(--bind="$2":"$2":ro) ; shift 2 ;;
            --pip)        local install_type=pip ;             shift   ;;
            --conda)      local install_type=conda ;           shift   ;;
            *)            local INSTALL_OPTS=("$@") ;          break   ;;
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

    # If force mode: delete the environment
    if test -n "$VENVA_FORCE" -a -e "$BASE"/venv.squashfs ; then
        echo "Deleting $BASE/venv.squashfs"
        rm -v "$BASE"/venv.squashfs
    fi

    # Detect what our mode should be (pip, conda, which requirements
    # file).  Priority to --pip or --conda, then environment.yml,
    # pylock.toml, requirements.txt in that order.
    if   [ "$install_type" = pip ] ; then
        if -z "$INSTALL_OPTS" ; then
            test -e requirements.txt && local INSTALL_OPTS=(-r requirements.txt)
            test -e pylock.toml && local INSTALL_OPTS=(-r pylock.toml)
        fi
    elif [ "$install_type" = conda ] ; then
        test -z "$INSTALL_OPTS" || local INSTALL_OPTS=(-f environment.yml)
    # One argument - requirements file
    elif [ "${#INSTALL_OPTS[@]}" -eq 1 ] ; then
        case "${INSTALL_OPTS[0]}" in
            *.txt|*.toml)
                local install_type=pip
                local INSTALL_OPTS=(-r "${INSTALL_OPTS[@]}")
            ;;
            *.yml)
                local install_type=conda
                local INSTALL_OPTS=(-f "${INSTALL_OPTS[@]}")
            ;;
        esac
    # Multi-arg options: install exactly with the args given
    elif [ -n "$INSTALL_OPTS" ] ; then
        local install_type=pip
    elif [ -e environment.yml ]  ; then local install_type=conda ; local INSTALL_OPTS=(-f environment.yml)
    elif [ -e pylock.toml ]      ; then local install_type=pip   ; local INSTALL_OPTS=(-r pylock.toml)
    elif [ -e requirements.txt ] ; then local install_type=pip   ; local INSTALL_OPTS=(-r requirements.txt)
    fi
    # Warn if nothing was detected
    if [ -z "$INSTALL_OPTS" ] ; then
        echo "No requirements file auto-detected"
        return 1
    fi
    echo "Installing ${INSTALL_OPTS[@]} with mode $install_type"

    # Handle Pip vs Conda specialities.
    local install_type install_command
    local IMG
    if [ "$install_type" = pip ] ; then
        if ! test -e "$VENV_APPTAINER_IMAGE" ; then
            apptainer pull "$VENV_APPTAINER_IMAGE" docker://python:3.13.14-trixie
        fi
        install_command="python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install ${INSTALL_OPTS[@]}"
        IMG="${IMG:-$VENV_APPTAINER_IMAGE}"
        mkdir -p "$HOME"/.cache/pip-apptainer
        BINDS+=("--bind=$HOME/.cache/pip-apptainer/:$HOME/.cache/pip")
        SQUASHFS_FILE=venv.squashfs
    elif [ "$install_type" = conda ] ; then
        if ! test -e "$CONDA_APPTAINER_IMAGE" ; then
            apptainer pull "$CONDA_APPTAINER_IMAGE" docker://condaforge/miniforge3:26.3.2-3
        fi
        install_command="conda env create --yes -p /venv-apptainer ${INSTALL_OPTS[@]}"
        IMG="${IMG:-$CONDA_APPTAINER_IMAGE}"
        mkdir -p "$HOME"/.cache/conda-apptainer "$HOME"/.conda-apptainer/
        BINDS+=("--bind=$HOME/.cache/conda-apptainer/:$HOME/.cache/conda/")
        BINDS+=("--bind=$HOME/.conda-apptainer/:$HOME/.conda/")
        SQUASHFS_FILE=conda-env.squashfs
    else
        echo "No requirements file found (requirements.txt or environment.yml)"
        return 1
    fi

    # Make the environment directories
    mkdir -p "$BASE"/venv
    mkdir -p "$BASE"/bin
    mkdir -p "$BASE"/tmp

    # Do the actual building
    apptainer exec \
              --bind="$BASE"/venv:"$PATH_IN" \
              --cwd "$PWD" \
              --bind "$PWD:$PWD" \
              "${BINDS[@]}" \
              --workdir="$BASE"/tmp \
              --contain --env LANG=C --env LC_ALL=C \
              "$IMG" \
              bash -c "$install_command"
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
        rm -r venva/venv/
    fi

    # Install the `$BASE/exec` wrapper that includes all the options
    # we need to run within the container.  This wrapper also
    # activates the environments within the container, then runs
    # either a shell or the command given on the command line.
    echo '#!/bin/bash' > "$BASE"/exec   # bash not ideal but needs better than sh
    echo 'BASE="$(dirname "$0")"' >> "$BASE"/exec
    echo "BINDS=($(printf '%q\n' "${BINDS[@]}"))" >> "$BASE"/exec
    if [ "$install_type" = pip ]; then
        echo apptainer exec $BIND_ENV \
             --contain --env LANG=C --env LC_ALL=C \
             --bind '"$PWD:$PWD"' '"${BINDS[@]}"' \
             --cwd '"$PWD"' '--workdir="$BASE"/tmp' \
             "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" - "$@"' \
             >> "$BASE/exec"
    elif [ "$install_type" = conda ] ; then
        echo apptainer exec $BIND_ENV \
             --contain --env LANG=C --env LC_ALL=C \
             --bind '"$PWD:$PWD"' '"${BINDS[@]}"' \
             --cwd '"$PWD"' '--workdir="$BASE"/tmp' \
             "$IMG" 'bash -c "source activate /venv-apptainer ; \${@:-bash}" - "$@"' \
             >> "$BASE"/exec
    fi
    chmod a+x "$BASE"/exec

    # In $BASE/bin/, install wrappers for all programs within the
    # environment (/venv-apptainer/bin/ on the container).  These
    # transparently run the respective programs within the container.
    for executable in $(./"$BASE"/exec ls "$PATH_IN"/bin/) ; do
        echo 'BASE="$(dirname "$0")/../"' > "$BASE"/bin/"$executable"
        echo '"$BASE"/exec' "$executable" '"$@"' >> "$BASE"/bin/"$executable"
        chmod a+x "$BASE"/bin/"$executable"
    done

    # Create the activate script, which adds the venv to the path.
    # The ${BASH_SOURCE:-${(%):-%x}} construct allows something like
    # BASH_SOURCE on zsh, too.
    echo 'PATH="$(realpath $(dirname "${BASH_SOURCE:-${(%):-%x}}"))"/bin/:"$PATH"' > "$BASE"/activate
    echo 'VIRTUAL_ENV="$(basename "$(dirname ${BASH_SOURCE:-${(%):-%x}})")"' >> "$BASE"/activate

    # Activate the environment
    source "$BASE"/activate
    #set +x
}
