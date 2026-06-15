VENV_APPTAINER_IMAGE=${VENV_APPTAINER_IMAGE:=$(readlink -f $(dirname $BASH_SOURCE)/python-3.14.sif)}
CONDA_APPTAINER_IMAGE=${CONDA_APPTAINER_IMAGE:=$(readlink -f $(dirname $BASH_SOURCE)/miniforge-26.sif)}

function vea() {
    #set -x
    local BASE PATH_IN PATH_OUT BIND_ENV APPTAINER_EXTRA
    BASE=venva
    PATH_IN=/venv-apptainer/
    PATH_OUT=$PWD/$BASE/venv/
    BIND_ENV=--bind=$PATH_OUT:$PATH_IN
    APPTAINER_EXTRA="--contain --cwd $PWD --bind $PWD:$PWD --workdir=$PWD/$BASE/tmp --env LANG=C --env LC_ALL=C"

    # Environment seems to already exist, so activate it.
    # Delete the $BASE (./venva/) directory to re-create.
    if test -e $BASE ; then
	PATH="$PWD"/$BASE/bin/:"$PATH"
	VIRTUAL_ENV=$BASE
	#set +x
	return
    fi

    mkdir -p $PATH_OUT
    mkdir -p $BASE/bin
    mkdir -p $BASE/tmp

    # Handle Pip vs Conda specialities.
    local install_type install_command
    local IMG BIND_CACHE
    if test -e requirements.txt ; then
	if ! test -e $VENV_APPTAINER_IMAGE ; then
	    apptainer pull $VENV_APPTAINER_IMAGE docker://python:3.13.14-trixie
	fi
	install_type='pip'
	install_command='python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install -r requirements.txt'
	IMG="$VENV_APPTAINER_IMAGE"
	mkdir -p $HOME/.cache/pip-apptainer
	BIND_CACHE=--bind=$HOME/.cache/pip-apptainer/:$HOME/.cache/pip
	SQUASHFS_FILE=venv.squashfs
    elif test -e environment.yml ; then
	if ! test -e $CONDA_APPTAINER_IMAGE ; then
	    apptainer pull $CONDA_APPTAINER_IMAGE docker://conda-forge/miniforge3:latest
	fi
	install_type='conda'
	install_command='conda env create --yes -p /venv-apptainer -f environment.yml'
	IMG="$CONDA_APPTAINER_IMAGE"
	mkdir -p $HOME/.cache/conda-apptainer $HOME/.conda-apptainer/
	BIND_CACHE="--bind=$HOME/.cache/conda-apptainer/:$HOME/.cache/conda/ --bind=$HOME/.conda-apptainer/:$HOME/.conda/"
	SQUASHFS_FILE=conda-env.squashfs
    else
	"No requirements file found (requirements.txt or environment.yml)"
	return 1
    fi

    # Do the actual building
    apptainer exec \
	      $BIND_ENV \
	      $BIND_CACHE \
	      $APPTAINER_EXTRA \
	      "$IMG" \
	      bash -c "$install_command"
    if [ $? -ne 0 ] ; then
	echo "Apptainer command failed"
	return 1
    fi

    # Make it a squashfs, if mksquashfs is installed.
    if type mksquashfs > /dev/null ; then
	mksquashfs $BASE/venv/ $BASE/$SQUASHFS_FILE
	PATH_OUT=$PWD/$BASE/$SQUASHFS_FILE
	BIND_ENV=--bind=$PATH_OUT:$PATH_IN:image-src=/
	rm -r venva/venv/
    fi

    # Install the `$BASE/exec` wrapper that includes all the options
    # we need to run within the container.  This wrapper also
    # activates the environments within the container, then runs
    # either a shell or the first command line options.
    if [ "$install_type" = pip ]; then
	echo apptainer exec $BIND_ENV $APPTAINER_EXTRA "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" - "$@"' > $BASE/exec
    elif [ "$install_type" = conda ] ; then
	echo apptainer exec $BIND_ENV $APPTAINER_EXTRA "$IMG" 'bash -c "source activate /venv-apptainer ; \${@:-bash}" - "$@"' > $BASE/exec
    fi
    chmod a+x $BASE/exec

    # In $BASE/bin/, install wrappers for all programs within the environment
    for executable in $(./$BASE/exec ls $PATH_IN/bin/) ; do
	echo "$PWD"/$BASE/exec "$executable" '"$@"' >> $BASE/bin/"$executable"
	chmod a+x $BASE/bin/"$executable"
    done

    # Activate the environment
    PATH="$PWD"/venva/bin/:"$PATH"
    VIRTUAL_ENV=venva
    #set +x
}
