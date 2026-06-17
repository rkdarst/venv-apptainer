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
  and builds the virtual environment there, always only *mounting*
  that directory inside the standard Python image (to save disk space).
* `$PWD` is mounted inside the container, but `$HOME` isn't.
  Apptainer is run with `--contain`.
* There is squashfs support to package up the environment and save
  inodes (default on).
* It's designed (via `#!` lines) to make it difficult to accidentally
  execute outside the container
* Handle pip/conda caches to avoid re-downloading things (it may
  result in vulnerable packages being cached, but the cache is not
  shared with the normal pip/conda cache.  Should it be, so that it
  can be cleaned more easily?)

Implementation details:

* `./venva/` is mounted inside the container at `/venv-apptainer/` and
  used to build the virtual environment.
* `./venva/exec` is a wrapper to exec inside the container (runs a
  shell, or arbitrary command you specify).
* `./venva/bin/` contains wrappers to execute all the scripts in the
  venv, inside the container.  This makes usage mostly transparent.


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

- Practical testing by others, to see if it's ready for broad aption.
- There are some bashisms that need fixing (mainly $BASH_SOURCE which
  doesn't have a general solution for getting the path of sourced
  scripts).
- There may be some nested unquoted variable expansions. (perhaps done)
- It will fail on directories with a `:` (colon) anywhere in the
  absolute path.
- Investigate locale handling


## See also

* `venv-apptainer1.sh` is the old version that does build a new image
  for every virtual environment.  Not up to date.
* Somewhat inspired by https://github.com/bast/apptainer-venv (but
  redesigned for more isolation and being similar to my previous
  `ve` alias).  `venv-apptainer2.sh` follows the lessons from here.
