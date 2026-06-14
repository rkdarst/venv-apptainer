VENV_APPTAINER_IMAGE=$(readlink -f $(dirname $BASH_SOURCE)/python-3.14.sif)

function vea() {
    #set -x
    local IMG
    IMG="$VENV_APPTAINER_IMAGE"
    local PATH_IN PATH_OUT
    PATH_IN=/venv-apptainer/
    PATH_OUT=venva/venv/

    if test -e venva/ ; then
	PATH="$PWD"/venva/venva-bin/:"$PATH"
	VIRTUAL_ENV=venva
	#set +x
	return
    fi

    mkdir -p $PATH_OUT
    mkdir -p venva/venva-bin/
    mkdir -p $HOME/.cache/pip-apptainer
    apptainer exec --no-home \
	      --bind $PWD/$PATH_OUT:$PATH_IN \
	      --bind $HOME/.cache/pip-apptainer/:$HOME/.cache/pip \
	      "$IMG" \
	      bash -c 'python3 -m venv /venv-apptainer ; source /venv-apptainer/bin/activate ; pip install -r requirements.txt'

    echo apptainer exec --no-home --bind $PWD/$PATH_OUT:$PATH_IN --env LANG= "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; \${@:-bash}" - "$@"' > venva/exec
    #echo apptainer exec --no-home --bind $PWD/venva:/venv --env LANG= "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; python \$@" - "$@"' > venva/python
    #echo apptainer exec --no-home --bind $PWD/venva:/venv --env LANG= "$IMG" 'bash -c "source /venv-apptainer/bin/activate ; pip \$@" - "$@"' > venva/pip
    chmod a+x venva/exec

    for executable in $(./venva/exec ls $PATH_IN/bin/) ; do
	echo "$PWD"/venva/exec "$executable" '"$@"' >> venva/venva-bin/"$executable"
	chmod a+x venva/venva-bin/"$executable"
    done

    PATH="$PWD"/venva/venva-bin/:"$PATH"
    VIRTUAL_ENV=venva
    #set +x
}
