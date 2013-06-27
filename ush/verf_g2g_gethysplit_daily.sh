#!/bin/ksh
#####################################################################
# This script obtains daily HYSPLIT SMOKE concentration data
#
# Author:  Jianping Huang
# History: 2011-11-01 Modified by Julia Zhu for running in production
#          environment
#
# Usage:   verf_g2g_gethysplit_daily.sh NEST VDAY
#####################################################################
set -x

if [[ $# -lt 2 ]]; then
  MSG="USAGE $0 NEST VDAY"
  echo $MSG
  err_exit
fi

export nest=$1
export vday=$2

export COPYGB=${COPYGB:-/nwprod/util/exec/copygb}

export COMHYSPT=${COMHYSPT:-/com/hysplit/prod}

case $nest in
  conus) hysplitdir=$COMHYSPT/smoke
         OUTDIR=$COM_OUT/smoke.$vday
#         binfile=bin_pbl.1hr_227
         gribfile=grib_pbl.1hr_227
#         gribfile=grib_pbl.t06z.1hr
         fhead=aod-smoke-cs
#         jmax=601
#         imax=251;;
#         vgrid=281
         jmax=1473
         imax=1025
         vgrid=227;;
  ak)    hysplitdir=$COMHYSPT/smokeak
         OUTDIR=$COM_OUT/smoke.$vday
#         binfile=binak_pbl.1hr_198
         gribfile=gribak_pbl.1hr_198
         fhead=aod-smoke-ak 
         vgrid=198
         jmax=825
         imax=553 ;;
  hi)    hysplitdir=$COMHYSPT/smokehi
         OUTDIR=$COM_OUT/smoke.$vday
#         binfile=binhi_pbl.1hr_196
         gribfile=gribhi_pbl.1hr_196
         fhead=aod-smoke-hi
         vgrid=196
         jmax=321
         imax=225 ;;
esac

# below added by jphuang for testing 
#export  hysplitdir=/meso/noscrub/wx20jh/aod-smoke/conc/hysplit
##
# Select NESDIS SAT Algorithm
# jp export algorithm=5

# fhead should be in consistent with file prefix opened in sorc/convert_*.f
export fhead=$fhead

#if [ -s ${hysplitdir}.$vday/$binfile ]
#then
#   cp ${hysplitdir}.$vday/$binfile .
#   cp ${hysplitdir}.$vday/$binfile ${OUTDIR}/.
#fi

if [ -s ${hysplitdir}.$vday/$gribfile ]
then
   cp ${hysplitdir}.$vday/$gribfile .
   cp ${hysplitdir}.$vday/$gribfile ${OUTDIR}/.
fi

if [ -s $gribfile ]; then
   echo "***** perform convert_hysplit directly"
#else
#   if [ -s $binfile ]; then
#      /nwprod/exec/hysplit_con2grib -g0 -m4 -i${binfile} -o${gribfile} -m4 -n25:72 -x1.0E+09 -r${vday}"06"
#   else
#      echo "***** "$binfile" not found in "$data
#      echo "***** program terminated"
#      err_exit
#   fi
fi

cat >input.prd <<EOF
$fhead
t06z
$jmax
$imax
EOF

pgm=verf_g2g_convert.hysplit
. $DATA/prep_step

##export XLFUNIT_10="$gribfile"

ln -sf $gribfile fort.10

$EXECverf_g2g/verf_g2g_convert.hysplit <input.prd >>conver_hysplit.out
err=$?; err_chk

#if [ $SENDCOM = YES ]
#then
#  cp ${fhead}.t06z.* $OUTDIR/.
#fi


# Convert to NESDIS data format using copygb
#if [ $nest = conus -o $nest = ak -o $nest = hi ]
#then
#jp  grid='255  0 801 534 0 -175000 128 80000 -55000 150 150 64 0 0 0 0 0'

  fst_beg=1
  fst_end=48

  fst=${fst_beg}

#  while [[ ${fst} -le ${fst_end} ]]; do
#    if [ $fst -lt 10 ]; then fst=0$fst; fi
#    export file1=${fhead}.t06z.f${fst}
#    export file2=${fhead}.t06z.grib${vgrid}.f${fst}
#    cp -rp $file1 $file2
# below was commented out by jphuang beause we verify grid198 of AK and grid 196 for HI
# no need of using copygb
#    export file2=${fhead}.t06z.grib255.f${fst}
#    echo "copygb at hour: "$fst
#    $COPYGB -g"$grid" -i2,1 -x $file1 $file2
#    if [ $nest = ak ] ; then
#     export file2=${fhead}.t06z.grib198.f${fst}
#    else
#     export file2=${fhead}.t06z.grib196.f${fst}
#    fi 

    if [ $SENDCOM = YES ]; then
#       cp $file2 $OUTDIR/.
      cp -rp ${fhead}.t06z.f* $OUTDIR/.
    fi

#    let fst=fst+1
#  done
#fi

echo "Done hypslit data conversion"
