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

    # Parse command line arguments.
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "usage: vea REQ_FILE"
                echo
                echo -- "REQ_FILE:      Use this requirements file (default: detect"
                echo -- "               environment.yml, pylock.toml, requirements.txt"
                echo -- "               in that order)"
                echo -- "--force:       force a rebuild"
                echo -- "--no-squash:   Don't compact to a squashfs filesystem.  Allows"
                echo -- "               updating/editing later"
                echo -- "--pip:         Install file with pip"
                echo -- "--conda:       Install file with conda"
                shift
                return
                ;;
            -f|--force)
                local VENVA_FORCE=true
                shift
                ;;
            --no-squash)
                local NO_SQUASH=true
                shift
                ;;
            --pip)
                local install_type=pip
                shift
                ;;
            --conda)
                local install_type=conda
                shift
                ;;
            *)
                local REQ_FILE="$1"
                shift
                ;;
        esac
    done

    # If the environment seems to already exist, so activate it and return.
    # Delete the $BASE (./venva/) directory to re-create.
    if test -z "$VENVA_FORCE" -a -e "$BASE" ; then
        #PATH="$PWD/$BASE/bin/":"$PATH"
        #VIRTUAL_ENV="$BASE"
        source "$BASE"/activate
        #set +x
        return
    fi

    # Detect what our mode should be (pip, conda, which requirements
    # file).  Priority to --pip or --conda, then environment.yml,
    # pylock.toml, requirements.txt in that order.
    if   [ "$install_type" = pip ] ; then
        if -n "$REQ_FILE" ; then
            test -e requirements.txt && local REQ_FILE=requirements.txt
            test -e pylock.toml && local REQ_FILE=pylock.toml
        fi
    elif [ "$install_type" = conda ] ; then
        test -n "$REQ_FILE" || local REQ_FILE=environment.yml
    elif [ -n "$REQ_FILE" ] ; then
        case "$REQ_FILE" in
            *.txt|*.toml)
                local install_type=pip
            ;;
            *.yml)
                local install_type=conda
            ;;
        esac
    elif [ -e environment.yml ]  ; then local install_type=conda ; local REQ_FILE=environment.yml
    elif [ -e pylock.toml ]      ; then local install_type=pip   ; local REQ_FILE=pylock.toml
    elif [ -e requirements.txt ] ; then local install_type=pip   ; local REQ_FILE=requirements.txt
    fi
    # Warn if nothing was detected
    if [ -z "$REQ_FILE" ] ; then
        echo "No requirements file auto-detected"
        return 1
    fi
    echo "Installing $REQ_FILE with mode $install_type"

    # Handle Pip vs Conda specialities.
    local install_type install_command
    local IMG BIND_CACHE
    if [ "$install_type" = pip ] ; then
        if ! test -e "$VENV_APPTAINER_IMAGE" ; then
            apptainer pull "$VENV_APPTAINER_IMAGE" docker://python:3.13.14-trixie
        fi
        install_command="python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install -r ${REQ_FILE:-requirements.txt}"
        IMG="$VENV_APPTAINER_IMAGE"
        mkdir -p "$HOME"/.cache/pip-apptainer
        BIND_CACHE=--bind="$HOME"/.cache/pip-apptainer/:"$HOME"/.cache/pip
        SQUASHFS_FILE=venv.squashfs
    elif [ "$install_type" = conda ] ; then
        if ! test -e "$CONDA_APPTAINER_IMAGE" ; then
            apptainer pull "$CONDA_APPTAINER_IMAGE" docker://condaforge/miniforge3:26.3.2-3
        fi
        install_command="conda env create --yes -p /venv-apptainer -f ${REQ_FILE:-environment.yml}"
        IMG="$CONDA_APPTAINER_IMAGE"
        mkdir -p "$HOME"/.cache/conda-apptainer "$HOME"/.conda-apptainer/
        BIND_CACHE="--bind=$HOME/.cache/conda-apptainer/:$HOME/.cache/conda/ --bind=$HOME/.conda-apptainer/:$HOME/.conda/"
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
              $BIND_CACHE \
              --cwd "$PWD" \
              --bind "$PWD:$PWD" \
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
    if [ "$install_type" = pip ]; then
        echo 'BASE="$(dirname $0)"' > "$BASE"/exec
        echo apptainer exec $BIND_ENV \
             --contain --env LANG=C --env LC_ALL=C \
             --cwd '"$PWD"' --bind '"$PWD:$PWD"' '--workdir="$BASE"/tmp' \
             "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" - "$@"' \
             >> $BASE/exec
    elif [ "$install_type" = conda ] ; then
        echo 'BASE="$(dirname $0)"' > "$BASE"/exec
        echo apptainer exec $BIND_ENV \
             --contain --env LANG=C --env LC_ALL=C \
             --cwd '"$PWD"' --bind '"$PWD:$PWD"' '--workdir="$BASE"/tmp' \
             "$IMG" 'bash -c "source activate /venv-apptainer ; \${@:-bash}" - "$@"' \
             >> "$BASE"/exec
    fi
    chmod a+x "$BASE"/exec

    # In $BASE/bin/, install wrappers for all programs within the
    # environment (/venv-apptainer/bin/ on the container).  These
    # transparently run the respective programs within the container.
    for executable in $(./"$BASE"/exec ls "$PATH_IN"/bin/) ; do
        echo 'BASE="$(dirname $0)/../"' > "$BASE"/bin/"$executable"
        echo "$BASE"/exec "$executable" '"$@"' >> "$BASE"/bin/"$executable"
        chmod a+x "$BASE"/bin/"$executable"
    done

    # Create the activate script, which adds the venv to the path.
    # The ${BASH_SOURCE:-${(%):-%x}} construct allows something like
    # BASH_SOURCE on zsh, too.
    echo 'PATH="$(realpath $(dirname ${BASH_SOURCE:-${(%):-%x}}))"/bin/:"$PATH"' > "$BASE"/activate
    echo 'VIRTUAL_ENV="$(basename $(dirname ${BASH_SOURCE:-${(%):-%x}}))"' >> "$BASE"/activate

    # Activate the environment
    source "$BASE"/activate
    #set +x
}
