SHELL=/bin/sh
#
SRCS=  setmissing.f90
OBJS=  setmissing.o
# Tunable parameters
#
# FC		Name of the fortran compiling system to use
# LDFLAGS	Flags to the loader
# LIBS		List of libraries
# CMD		Name of the executable
# PROFLIB	Library needed for profiling
#
#FC =	 ifort	
#LDFLAGS = -p -bnoquiet -bloadmap:mug
#LDFLAGS = -pg
#INC = /nwprod/lib/incmod/g2_4
#LIBS = -L/nwprod/lib -lg2_4 -lw3nco_v2.0.3_4 -lbacio_4 -ljasper -lpng -lz

CMD =	wafs_setmissing
#PROFLIB =	-lprof

# To perform the default compilation, use the first line
# To compile with flowtracing turned on, use the second line
# To compile giving profile additonal information, use the third line
# WARNING:  SIMULTANEOUSLY PROFILING AND FLOWTRACING IS NOT RECOMMENDED 
#FFLAGS =	-O -I$(INC)
FFLAGS =	${FFLAGSblnd}
#FFLAGST =       -O -FR -I$(INC)

# Lines from here on down should not need to be changed.  They are the
# actual rules which make uses to build a.out.
#
.SUFFIXES:	.f .o .f90

$(CMD):		$(OBJS)
	$(FC) $(LDFLAGS) -o $(@) $(OBJS) $(LIBS)

.f.o:
	$(FC) $(FFLAGS) -c $<
.f90.o:
	$(FC) $(FFLAGST) -c $<

clean:
	-rm -f $(OBJS)

clobber:	clean
	-rm -f $(CMD) $(CMD).prof

void:	clobber
	-rm -f $(SRCS) makefile

install:
	mv $(CMD) ../../exec/.
