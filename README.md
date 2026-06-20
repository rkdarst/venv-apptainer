# Python virtual environments in Apptainer for supply-chain attack protection

`venv-apptainer2.sh` adds a shell function `vea` builds virtual
environments in apptainer to protect against supply chain attacks.
(Note that containers are not perfect protection).  Anyone can
manually build containers when needed, but this makes it automatic.
Basically:

* You have a project directory with `requirements.txt` or
  `environment.yml`.
* You run the shell function `vea` (sourced in .bashrc)
* Environment is built in a container and wrapper scripts are added to
  `$PATH`.  If it already exists in the current dir, activate it
  instead.
* Everything is stored in `./venva/`.  Delete or move the dir to
  rebuild.

It doesn't make a container with the environment within it (that was
an old approach in `venv-apptainer1.sh`), the environment is built and
stored outside and bound inside (and the container image is completely
standard `python`).

`vea` builds or activates the environment.  Basically, change to the
dir and run `vea`, and you'll get set up with a old or new setup.

There is preliminary support for Conda, which is activated when a
environment.yml file is detected.  `zsh` should also be supported but
it needs testing.


## Status and development

This should work but is still in testing.  Report issues and they are
likely to be fixed (as of 2026).

This was also mainly designed for my own use to replace my old `ve`
alias, but then I did more work so that it might be useful to others.
If it does become useful, I will work to improve documentation and
code further.


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
shell function.  This is designed to be sourced from .bashrc.  It
should support at least bash and zsh.

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
$ vea [req_file]               # Use this as the requirements.txt file.
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

When installing,

* `vea FILENAME` will use that as the requiremnets file.  `*.txt` and
  `*.toml` will be installed with pip and `*.yml` will be installed
  with conda.
* `vea --conda` will force conda mode and use `environment.yml` by
  default.
* `vea --pip` will force pip mode and detect `pylock.toml` and
  `requirements.txt` in that order.


## To do

- Practical testing by others, to see if it's ready for broad aption.
- There may be some nested unquoted variable expansions. (perhaps done)
- It will fail on directories with a `:` (colon) anywhere in the
  absolute path.
- Investigate locale handling


## Other notes

- To ignore `venva/` directories, I recommend setting `git config
  --global core.excludesfile ~/.gitignore` and then setting your
  personal workflow's exclusions in `~/.gitignore` (such as
  `/venva/`), rather than copy it to every repository you work on.

## `venv-apptainer1.sh`

This was an older version of this project (it minimally worked, but
not enough to really use).  It was designed to build a new, separate
container for every environment, with only `$PWD` mounted inside of
it.

Don't use it as it is, but if you want me to fix it up, let me know.


## See also

* Somewhat inspired by https://github.com/bast/apptainer-venv (but
  redesigned for more isolation and being similar to my previous
  `ve` alias).  `venv-apptainer2.sh` follows the lessons from here.
* Tool for creating minimal envs in a container:
  https://github.com/simo-tuomisto/micromamba-apptainer
