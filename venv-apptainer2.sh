set -x

IMG=python-3.14.sif

mkdir -p venv
apptainer exec --no-home --bind $PWD/venv/:/venv "$IMG" bash -c 'python3 -m venv /venv ; source /venv/bin/activate ; pip install -r requirements.txt'

#test -L python && rm python
#test -L pip    && rm pip
#ln -s venv.sif python
#ln -s venv.sif pip
echo apptainer exec --no-home --bind $PWD/venv:/venv --env LANG= "$IMG" 'bash -c "source /venv/bin/activate ; python \$@" - "$@"' > python
echo apptainer exec --no-home --bind $PWD/venv:/venv --env LANG= "$IMG" 'bash -c "source /venv/bin/activate ; \${@:-bash}" - "$@"' > exec
echo apptainer exec --no-home --bind $PWD/venv:/venv --env LANG= "$IMG" 'bash -c "source /venv/bin/activate ; pip \$@" - "$@"' > pip
chmod a+x pip python exec
