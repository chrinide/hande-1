#!/usr/bin/python
'''Produce a makefile for compiling the source code for a specified target/configuration.

Usage:
    mkconfig.py [options] [configuration_file]

Use the --help option to see more details.

A platform is defined using a simple ini file, consisting of three sections:
main, opt and dbg.  For instance::

    [main]
    cc = gfortran
    ld = gfortran
    libs = -llapack -lblas

    [opt]
    cflags = -O3

    [dbg]
    cflags = -g

The 'opt' and 'dbg' sections inherit settings from the 'main' section.  The settings
in 'opt' are used by default; the debug options can be selected by passing the
-g option to mkconfig.py.

Available options are:

fc
    Set the fortran compiler.
fflags
    Set flags to be passed to the fortran compiler during compilation.
cppdefs
    Set definitions to be used in the C pre-processing step.
cppflags
    Set flags to be used in the C pre-processing step.
ld
    Set the linker program.
ldflags
    Set flags to be passed to the linker during linking of the compiled objects.
libs
    Set libraries to be used during the linking step.
module_flag
    Set the flag used by the compiler which is used to specify the directory
    where module (.mod) files are placed when created and where they should be
    searched for.
'''

import ConfigParser
import optparse
import os
import pprint
import sys

#======================================================================
# Local settings.

PROGRAM_NAME='hubbard.x'

(PROGRAM_STEM, PROGRAM_EXT) = os.path.splitext(PROGRAM_NAME)

# Directory in which compiled objects are placed.
DEST='dest'

# Directory in which the compiled executable is placed.
EXE='bin'

# List of directories (colon-separated) containing the source files.
VPATH='src:lib'

# Space separated list of file extensions for the source files.
SOURCE_EXT='.f90 .F90'

#======================================================================

MAKEFILE_TEMPLATE='''# Generated by mkconfig.py.

SHELL=/bin/bash # For our sanity!

# Name of this makefile.
my_makefile := $(word $(words $(MAKEFILE_LIST)), $(MAKEFILE_LIST))
# Command used to recursively call *this* makefile.
my_make := $(MAKE) -f $(my_makefile)

#-----
# Compiler configuration.

FC=%(fc)s
FFLAGS=-I $(DEST) %(fflags)s

CPPDEFS = %(cppdefs)s -D_VCS_VERSION='$(VCS_VERSION)'
CPPFLAGS = %(cppflags)s $(WORKING_DIR_CHANGES)

LD = %(ld)s
LDFLAGS = %(ldflags)s
LIBS = %(libs)s

#-----
# Directory structure and setup.

# Config info.
CONFIG = %(config)s
OPT = %(opt_level)s

# Directories containing source files.
VPATH = %(VPATH)s

# Directory for objects.
DEST = %(DEST)s/$(CONFIG)/$(OPT)

# Directory for compiled executables.
EXE = %(EXE)s

# We put compiled objects and modules in $(DEST).  If it doesn't exist, create it.
make_dest := $(shell test -e $(DEST) || mkdir -p $(DEST))

# We put the compiled executable in $(EXE).  If it doesn't exist, then create it.
make_exe := $(shell test -e $(EXE) || mkdir -p $(EXE))

# Specific version of binary.
PROG_VERSION = %(PROGRAM_STEM)s.$(CONFIG).$(OPT)%(PROGRAM_EXT)s

# Symbolic link which points to $(PROG_VERSION).
PROG = %(PROGRAM)s

#-----
# Find source files and resultant object files.

# Source extensions.
EXTS = %(SOURCE_EXT)s

# Space separated list of source directories.
SRCDIRS := $(subst :, ,$(VPATH))

# Source filenames.
find_files = $(foreach ext,$(EXTS), $(wildcard $(dir)/*$(ext)))
SRCFILES := $(foreach dir,$(SRCDIRS),$(find_files))

# Objects (strip path and replace extension of source files with .o).
OBJ := $(addsuffix .o,$(basename $(notdir $(SRCFILES))))

# Full path to all objects.
OBJECTS := $(addprefix $(DEST)/, $(OBJ))

#-----
# VCS info.

# Get the version control id.  Git only.  Outputs a string.
VCS_VERSION := $(shell set -o pipefail && echo -n \\" && ( git log --max-count=1 --pretty=format:%%H || echo -n 'Not under version control.' ) 2> /dev/null | tr -d '\\r\\n'  && echo -n \\")

# Test to see if the working directory contains changes.  Git only.  If the
# working directory contains changes (or is not under version control) then
# the _WORKING_DIR_CHANGES flag is set.
WORKING_DIR_CHANGES := $(shell git diff --quiet --cached -- $(SRCDIRS) && git diff --quiet -- $(SRCDIRS) 2> /dev/null || echo -n "-D_WORKING_DIR_CHANGES")

#-----
# Dependency file.

DEPEND = %(DEST)s/.depend

#-----
# Compilation macros.

.SUFFIXES:
.SUFFIXES: $(EXTS)

# Files to be pre-processed then compiled.
$(DEST)/%%.o: %%.F90
\t$(FC) $(CPPDEFS) $(CPPFLAGS) -c $(FFLAGS) $< -o $@ %(module_flag)s$(DEST)

# Files to compiled directly.
$(DEST)/%%.o: %%.f90
\t$(FC) -c $(FFLAGS) $< -o $@ %(module_flag)s$(DEST)

#-----
# Goals.

.PHONY: clean test tests depend help $(PROG)

# Compile program.
$(PROG): $(EXE)/$(PROG_VERSION)
\tcd $(EXE) && ln -s -f $(notdir $<) $@

$(EXE)/$(PROG_VERSION): $(OBJECTS)
\t$(my_make) -B $(DEST)/environment_report.o
\ttest -e `dirname $@` || mkdir -p `dirname $@`
\t$(FC) -o $@ $(FFLAGS) $(LDFLAGS) -I $(DEST) $(OBJECTS) $(LIBS)

# Remove compiled objects and executable.
clean: 
\trm -f $(DEST)/*.{d,o} $(EXE)/$(PROG_VERSION)

cleanall:
\trm -rf %(DEST)s $(EXE)

# Build from scratch.
new: clean $(PROG)

# Run tests.
test:
\tcd test_suite && testcode.py

tests: test

# Generate dependency file.
$(DEPEND):
\ttools/sfmakedepend --file - --silent $(SRCFILES) --objdir \$$\(DEST\) --moddir \$$\(DEST\) > $@

depend: 
\t$(my_make) -B $(DEPEND)

help:
\t@echo "Please use 'make <target>' where <target> is one of:"
\t@echo "  %(PROGRAM)-14s       [default target] Compile program in the %(EXE)s directory."
\t@echo "  clean                Remove the compiled objects."
\t@echo "  ctags                Run ctags on the source files.  This is performed by default at the end of a successful compilation."
\t@echo "  new                  Remove all previously compiled objects and re-compile."
\t@echo "  tests                Run test suite."
\t@echo "  test                 Run test suite."
\t@echo "  depend               Produce the .depend file containing the dependencies."
\t@echo "                       Requires the makedepf90 tool to be installed."
\t@echo "  help                 Print this help message."

#-----
# Include dependency file.

# $(DEPEND) will be generated if it doesn't exist.
include $(DEPEND)
'''

def parse_options(my_args):
    '''Parse command line options given in the my_args list.

Returns the options object and a space separated list of configuration files.'''
    parser = optparse.OptionParser(usage='''mkconfig.py [options] [configuration_file(s)]

If no configuration file is given then the .default file in the specified directory is used.
A configuration file does not need to be specified with the --ls and --print options.
Multiple configuration files can only be given in conjunction with the --print option.''')
    parser.add_option('-d', '--dir', default='config/', help='Set directory containing the configuration files. Default: %default.')
    parser.add_option('-g', '--debug', action='store_true', default=False, help='Use the debug settings.  Default: use optimised settings.')
    parser.add_option('-l', '--ls', action='store_true', default=False, help='Print list of available configurations.')
    parser.add_option('-o', '--out', default='Makefile', help='Set the output filename to which the makefile is written.  Use -o - to write to stdout.  Default: %default.')
    parser.add_option('-p', '--print', dest='print_conf', action='store_true', default=False, help='Print settings in configuration file(s) specified, or all settings if no configuration file is specified.')

    (options, args) = parser.parse_args(my_args)

    if len(args) >= 1:
        config_file = ' '.join(os.path.join(options.dir, c) for c in args)
    elif len(args) == 0 and os.path.exists(os.path.join(options.dir, '.default')):
        config_file = os.path.join(options.dir, '.default')
    else:
        config_file = None

    if not (options.print_conf or options.ls):
        if len(args) > 1:
            print 'Incorrect arguments.'
            parser.print_help()
            sys.exit(1)
        if not config_file:
            print '.default file not found.'
            parser.print_help()
            sys.exit(1)

    return (options, config_file)

def list_configs(config_dir):
    '''Return the path to all config files in config_dir.  We assume only config files are in config_dir'''
    if os.path.isdir(config_dir):
        return [os.path.join(config_dir, f) for f in os.listdir(config_dir)]
    else:
        raise IOError, 'Config directory specified is not a directory: %s.' % (config_dir)

def parse_config(config_file):
    '''Parse the configuration file config_file.'''
    parser = ConfigParser.RawConfigParser()

    valid_sections = ['main', 'opt', 'dbg']

    valid_sections_upper = [s.upper() for s in valid_sections]

    valid_options = ['fc', 'fflags', 'cppdefs', 'cppflags', 'ld', 'ldflags', 'libs', 'module_flag']

    minimal_options = ['fc', 'ld', 'libs', 'module_flag']

    if not os.path.exists(config_file):
        raise IOError,'Config file does not exist: %s' % (config_file)

    parser.read(config_file)

    for s in parser.sections():
        if s not in valid_sections and s not in valid_sections_upper:
            raise IOError, 'Invalid section in configuration file %s: %s.' % (config_file, s)

    for s in valid_sections:
        if s not in parser.sections() and s.upper() not in parser.sections():
            raise IOError, 'Section not present in configuration file %s: %s.' % (config_file, s)             

    if not parser.sections():
        raise IOError, 'No sections in configuration file %s: %s.' % (config_file, s)

    config = {}

    for s in valid_sections:
        config[s] = dict(parser.items('main'))
        if s in parser.sections():
            config[s].update(parser.items(s))
        elif s.upper() in parser.sections():
            config[s].update(parser.items(s.upper()))

    for s in valid_sections:
        for opt in config[s].keys():
            if opt not in valid_options:
                raise IOError, 'Invalid option in configuration file: %s.' % (opt)
        # Fill in blanks
        for opt in valid_options:
            if opt not in config[s].keys():
                config[s][opt] = ''

    config.pop('main')

    for s in config.keys():
        # Check minimal options.
        for opt in minimal_options:
            if not config[s][opt]:
                raise IOError, 'Required option not set: %s' % (opt)
        # Treat module_flag specially: append a space if it doesn't end in =.
        # This is to allow the same template to be used no matter how the compiler
        # insists on handling this flag.
        if not config[s]['module_flag'][-1] == '=':
            config[s]['module_flag'] = '%s ' % (config[s]['module_flag'])

    return config

def create_makefile(config_file, use_debug=False):
    '''Returns the makefile using the options given in the config_file.'''
    if use_debug:
        config = parse_config(config_file)['dbg']
        config.update(opt_level='debug')
    else:
        config = parse_config(config_file)['opt']
        config.update(opt_level='optimised')
    # Set the name in the Makefile to be the basename of the config filename.  Follow any links.
    if os.path.islink(config_file):
        config_name = os.path.basename(os.readlink(config_file))
    else:
        config_name = os.path.basename(config_file)
    config.update(PROGRAM=PROGRAM_NAME, PROGRAM_STEM=PROGRAM_STEM, PROGRAM_EXT=PROGRAM_EXT, DEST=DEST, EXE=EXE, VPATH=VPATH, SOURCE_EXT=SOURCE_EXT, config=config_name)
    return MAKEFILE_TEMPLATE % (config)

if __name__=='__main__':
    args=sys.argv[1:]
    (options, config_file) = parse_options(args)
    if options.ls:
        print 'Available configurations are: %s.' % (', '.join(list_configs(options.dir)))
    elif options.print_conf:
        if config_file:
            config_files = config_file.split()
        else:
            config_files = list_configs(options.dir)
        for config_file in config_files:
            config = parse_config(config_file)
            print 'Settings in configuration file: %s' % (config_file)
            pprint.pprint(config)
            print
    else:
        if options.out == '-':
            f = sys.stdout
        else:
            f = open(options.out, 'w')
        f.write(create_makefile(config_file, options.debug))
        if options.out != '-':
            f.close()
