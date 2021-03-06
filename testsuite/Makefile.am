## Process this file with automake to produce Makefile.in

## Copyright (C) 2002 M. Marques, A. Castro, A. Rubio, G. Bertsch
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2, or (at your option)
## any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
## 02111-1307, USA.
##
## $Id: Makefile.am 6584 2010-05-03 18:22:50Z xavier $

SUBDIRS = \
	components       \
	finite_systems_1d finite_systems_2d finite_systems_3d \
	functionals      \
	real_time        \
	linear_response  \
	optimal_control  \
	periodic_systems \
	open_systems

bin_SCRIPTS = oct-run_regression_test.pl oct-run_testsuite

EXTRA_DIST = oct-run_regression_test.pl oct-run_testsuite.in

# OCTOPUS_SHARE has to be set to an absolute path because
# oct-run_testsuite changes the working directory for every
# testcase.
# If the testsuite should be skipped, e. g. in make distcheck,
# set the environment variable SKIP_CHECK to some value.
check:
	@if test "x$(SKIP_CHECK)" == "x"; then \
	    base=`basename "$(top_builddir)/share"` && \
	    dir=`dirname "$(top_builddir)/share"` && \
	    sharedir="`(cd \"$$dir\" 2> /dev/null && pwd || echo \"$$dir\")`/$$base" && \
	    OCTOPUS_SHARE=$$sharedir ./oct-run_testsuite -c -d $(srcdir) -l -g short-run; \
	else \
	    echo "Skipping checks"; \
	fi

check-full:
	@if test "x$(SKIP_CHECK)" == "x"; then \
	    base=`basename "$(top_builddir)/share"` && \
	    dir=`dirname "$(top_builddir)/share"` && \
	    sharedir="`(cd \"$$dir\" 2> /dev/null && pwd || echo \"$$dir\")`/$$base" && \
	    OCTOPUS_SHARE=$$sharedir ./oct-run_testsuite -c -d $(srcdir) -l; \
	else \
	    echo "Skipping checks"; \
	fi

clean-local:
	-find /tmp -name 'octopus*' -type d -mmin +600 -exec rm -rf {} \; 2>/dev/null

.PHONY: check check-full clean clean-local
