# Store images in ~/sys/ if it exists.  Otherwise in the location of
# this script.
if [ -d ~/sys/ ] ; then
    : "${VENV_APPTAINER_IMAGE:=$HOME/sys/python-3.14.sif}"
    : "${CONDA_APPTAINER_IMAGE:=$HOME/sys/miniforge-26.sif}"
else
    : "${VENV_APPTAINER_IMAGE:=$(realpath \"$(dirname \\\"$BASH_SOURCE\\\")/python-3.14.sif)\"}"
    : "${CONDA_APPTAINER_IMAGE:=$(realpath \"$(dirname \\\"$BASH_SOURCE\\\")/miniforge-26.sif)\"}"
fi

function vea() {
    #set -x
    local BASE=venva
    local PATH_IN=/venv-apptainer/

    while [[ $# -gt 0 ]]; do
	case $1 in
	    -h|--help)
		echo "usage: vea REQ_FILE"
		shift
		exit
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

    local APPTAINER_EXTRA="--contain --cwd \$PWD --bind \$PWD:\$PWD --workdir=\$BASE/tmp --env LANG=C --env LC_ALL=C"

    # Environment seems to already exist, so activate it.
    # Delete the $BASE (./venva/) directory to re-create.
    if test -z "$VENVA_FORCE" -a -e "$BASE" ; then
	#PATH="$PWD/$BASE/bin/":"$PATH"
	#VIRTUAL_ENV="$BASE"
	source "$BASE"/activate
	#set +x
	return
    fi

    mkdir -p "$BASE"/venv
    mkdir -p "$BASE"/bin
    mkdir -p "$BASE"/tmp

    # Handle Pip vs Conda specialities.
    local install_type install_command
    local IMG BIND_CACHE
    if [ "$install_type" = pip ] || { test -z "$install_type" && test -e requirements.txt ; } ; then
	if ! test -e "$VENV_APPTAINER_IMAGE" ; then
	    apptainer pull "$VENV_APPTAINER_IMAGE" docker://python:3.13.14-trixie
	fi
	install_type='pip'
	install_command='python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install -r ${REQ_FILE:-requirements.txt}'
	IMG="$VENV_APPTAINER_IMAGE"
	mkdir -p "$HOME"/.cache/pip-apptainer
	BIND_CACHE=--bind="$HOME"/.cache/pip-apptainer/:"$HOME"/.cache/pip
	SQUASHFS_FILE=venv.squashfs
    elif [ "$install_type" = conda ] || { test -z "$install_type" && test -e environment.yml ; } ; then
	if ! test -e "$CONDA_APPTAINER_IMAGE" ; then
	    apptainer pull "$CONDA_APPTAINER_IMAGE" docker://condaforge/miniforge3:26.3.2-3
	fi
	install_type='conda'
	install_command="conda env create --yes -p /venv-apptainer -f ${REQ_FILE:-environment.yml}"
	IMG="$CONDA_APPTAINER_IMAGE"
	mkdir -p "$HOME"/.cache/conda-apptainer "$HOME"/.conda-apptainer/
	BIND_CACHE="--bind=$HOME/.cache/conda-apptainer/:$HOME/.cache/conda/ --bind=$HOME/.conda-apptainer/:$HOME/.conda/"
	SQUASHFS_FILE=conda-env.squashfs
    else
	echo "No requirements file found (requirements.txt or environment.yml)"
	return 1
    fi

    # Do the actual building
    apptainer exec \
	      --bind="$BASE"/venv:"$PATH_IN" \
	      $BIND_CACHE \
	      $(eval echo $APPTAINER_EXTRA) \
	      "$IMG" \
	      bash -c "$install_command"
    if [ $? -ne 0 ] ; then
	echo "Apptainer command failed"
	return 1
    fi

    # Note that this is \$BASE - $BASE gets interperted at the point
    # of execution of the ./venva/exec script, so that it is relocateable!
    # This is default without squashfs:
    local BIND_ENV="--bind=\$BASE/venv:$PATH_IN"

    # Make it a squashfs, if mksquashfs is installed.
    if test -z "$NO_SQUASH" && type mksquashfs > /dev/null ; then
	mksquashfs "$BASE"/venv/ "$BASE/$SQUASHFS_FILE"
	BIND_ENV="--bind=\$BASE/$SQUASHFS_FILE:$PATH_IN:image-src=/"
	rm -r venva/venv/
    fi

    # Install the `$BASE/exec` wrapper that includes all the options
    # we need to run within the container.  This wrapper also
    # activates the environments within the container, then runs
    # either a shell or the first command line options.
    if [ "$install_type" = pip ]; then
	echo 'BASE=$(dirname $0)' > "$BASE"/exec
	echo apptainer exec $BIND_ENV $APPTAINER_EXTRA "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" - "$@"' >> $BASE/exec
    elif [ "$install_type" = conda ] ; then
	echo 'BASE=$(dirname $0)' > "$BASE"/exec
	echo apptainer exec $BIND_ENV $APPTAINER_EXTRA "$IMG" 'bash -c "source activate /venv-apptainer ; \${@:-bash}" - "$@"' >> "$BASE"/exec
    fi
    chmod a+x "$BASE"/exec

    # Activate script
    echo 'PATH="$(realpath $(dirname $BASH_SOURCE))"/bin/:"$PATH"' > "$BASE"/activate
    echo 'VIRTUAL_ENV="$(basename $(dirname $BASH_SOURCE))"' >> "$BASE"/activate


    # In $BASE/bin/, install wrappers for all programs within the environment
    for executable in $(./"$BASE"/exec ls "$PATH_IN"/bin/) ; do
	echo "$PWD/$BASE"/exec "$executable" '"$@"' >> "$BASE"/bin/"$executable"
	chmod a+x "$BASE"/bin/"$executable"
    done

    # Activate the environment
    #PATH="$PWD"/venva/bin/:"$PATH"
    #VIRTUAL_ENV=venva
    source "$BASE"/activate
    #set +x
}
