# Python virtual environments in Apptainer for supply-chain attack protection

This builds virtual environments in apptainer to protect against
supply chain attacks.  Note that containers are not perfect
protection.

The general idea is that a shell alias `vea` automatically builds the
environment from `./requirements.txt` at `./venva/`.  The actual
environment files are not put into a container, they are normal files
on disk (and the container image is completely standard `python`).
The shell alias also activates a path (`./venva/venva-bin/`) that
transparently runs commands within the container.

*Not fully documented yet, since it's still in development.  It's also
designed around my own tastes.*


## The concept / design criteria

* Run the shell alias `vea` build an environment at `./venva` if it
  doesn't exist (and activate it).  If it does exist, activate it.
  Remove `./venva` to force a rebuild.
* It doesn't build a new container for every environment (that was too
  high-resource for my tastes).  Instead, it creates a directory
  `./venva` and builds the virtual environment there, always re-using
  *only* the standard Python image.
* `$PWD` is mounted inside the container, but `$HOME` isn't.
* `./venva` is mounted inside the container at `/venv-apptainer` and
  used to build the virtual environment.
* `./venva/exec` is a wrapper to exec inside the container.
* `./venva/venva-bin/` contains wrappers to execute all the scripts in
  the venv, inside the container.
* It's designed (via `#!` lines) to make it difficult to accidentally
  execute outside the container


## Usage

```console

$ apptainer pull python-3.14.sif docker://python:3.14
                               # Get the raw Python image

$ source venv-apptainer2.sh    # could be put in .bashrc

$ vea                          # Build from requirements.txt in this directory
$ vea                          # Activate if it already exists
                               # ./venva/venva-bin is added to the path.

python                         # execute ./venva/venva-bin/python,
                               # which executes python inside the
							   # virtual env.
```

## See also

* `venv-apptainer1.sh` is the old version that does build a new image
  for every virtual environment.
* Somewhat inspired by https://github.com/bast/apptainer-venv (but
  redesigned for more isolation and being similar to my previous
  system).  `venv-apptainer2.sh` is more like this.
