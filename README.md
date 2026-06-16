# Python virtual environments in Apptainer for supply-chain attack protection

`venv-apptainer2.sh` adds a shell function `vea` builds virtual
environments in apptainer to protect against supply chain attacks.
Note that containers are not perfect protection.

The general idea is that a shell alias `vea` automatically builds the
environment from `./requirements.txt` at `./venva/`.  It doesn't make
a container with the environment within it (that was
`venv-apptainer1.sh`), the environment is built and stored outside and
bound inside (and the container image is completely standard
`python`).  The shell alias also activates a path (`./venva/bin/`)
that transparently runs commands within the container.

If an environment already exists, `vea` activates it.  That way, `vea`
will set you up no matter your current state.

There is preliminary support for Conda, which is activated when a
environment.yml file is detected.

*Not fully documented yet, since it's still in development.  It's also
designed around my own tastes.*


## The concept / design criteria

* Run the shell alias `vea` build an environment at `./venva/` if it
  doesn't exist (and activate it).  If it does exist, activate it.
  Remove `./venva/` to force a rebuild.
* It doesn't build a new container for every environment (that was too
  heavy for my tastes).  Instead, it creates a directory `./venva/`
  and builds the virtual environment there, always re-using *only* the
  standard Python image to save disk space.
* `$PWD` is mounted inside the container, but `$HOME` isn't.
  Apptainer is run with `--contain`.
* `./venva/` is mounted inside the container at `/venv-apptainer/` and
  used to build the virtual environment.
* `./venva/exec` is a wrapper to exec inside the container (runs a
  shell, or arbitrary command you specify).
* `./venva/bin/` contains wrappers to execute all the scripts in the
  venv, inside the container.  This makes usage mostly transparent.
* There is squashfs support to package up the environment and save
  inodes (default on).
* It's designed (via `#!` lines) to make it difficult to accidentally
  execute outside the container


## Usage

Source the script.  This doesn't do anything but defines the `vea`
shell function.  This is designed to be sourced from .bashrc.

```console
$ source venv-apptainer2.sh
```

Pulling happens automatically now.  If there is a ~/sys/ directory
images will be stored there automatically.  Images and Python versions
are currently hard-coded.  Otherwise stored in the location of the
`venv-apptainer2.sh` script.
```console
$ apptainer pull python-3.14.sif docker://python:3.14
                               # Get the raw Python image
```

Basic usage.  The principle is `vea` either builds/activates whatever
the state is.
```console
$ source venv-apptainer2.sh    # could be put in .bashrc

$ vea                          # Build from requirements.txt in this directory
$ vea                          # Activate if it already exists
                               # ./venva/bin is added to PATH.

$ python                       # execute ./venva/bin/python,
                               # which executes python inside the
							   # virtual env.

$ ./venva/exec [command]       # Run shell or command in the container
```

Force a rebuild:
```console
$ rm -r venva/
$ vea
```


## To do

- It's generally not ready for broad adoption.  In principle it works
  but small things are being worked out.  Others can use if they would
  look at teh source and/or ask for help.
- There are some bashisms that need fixing (mainly $BASH_SOURCE which
  doesn't have a general solution for sourced scripts).
- There may be some nested unquoted variable expansions.
- Make environment relocatable (currently bind paths are hardcoded and
  need to be relative to the `venva` directory).  Though this is how
  virtual environments are anyway now...
- Handle --cwd properly (currently hard-coded to base directory)


## See also

* `venv-apptainer1.sh` is the old version that does build a new image
  for every virtual environment.  Not up to date.
* Somewhat inspired by https://github.com/bast/apptainer-venv (but
  redesigned for more isolation and being similar to my previous
  `ve` alias).  `venv-apptainer2.sh` follows the lessons from here.
