set -x
apptainer build --force "$@" venv.sif /dev/stdin <<'EOF'

Bootstrap: docker
From: python:{{ PYTHON }}

%arguments
	PYTHON=3.14
	DEPS=requirements.txt

%files
	{{ DEPS }}

%post
	pip install -r requirements.txt

%runscript
	if [ -z "$APPTAINER_NOHOME_ENFORCED" ]; then
  	  export APPTAINER_NOHOME_ENFORCED=1
	  exec apptainer exec --no-home "$SINGULARITY_CONTAINER" "$@"
	fi

	python "$@"

%help
	A container built to host python.

%apprun pip
	pip "$@"

%apphelp pip
	 Run pip

%apprun exec
	"$@"


EOF

#test -L python && rm python
#test -L pip    && rm pip
#ln -s venv.sif python
#ln -s venv.sif pip
echo apptainer exec --no-home $(readlink -f .)/venv.sif python '"$@"' > python
echo apptainer exec --no-home $(readlink -f .)/venv.sif pip '"$@"' > pip
chmod a+x pip python
