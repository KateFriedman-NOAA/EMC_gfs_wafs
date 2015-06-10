#!/bin/ksh

#BSUB -oo 
#BSUB -eo 
#BSUB -J 
#BSUB -W 01:00
#BSUB -q "dev_shared"
#BSUB -R span[ptile=1]
#BSUB -n 1
#BSUB -R "rusage[mem=1024]" -R "affinity[core]"
#BSUB -a poe
#BSUB -P GFS-T2O

set -x

#---------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------
#  Purpose: Make plots that compare:  rmse, bias, pattern correlation, RMSE due to mean difference
#           RMSE due to pattern variation, ratio of standard deviation, from all centers for the 
#           same forecast cycle (e.g. 00Z)
#  1. Map plots show distributions as a function of pressure and calendar day for a given forecast time 
#  2. Line plots show results on a single isobaric layer as a function of calendar day for a given forecast time 
#  Fanglin Yang, April 2007; Updated Nov 2010.
#---------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------
date

export WEBSERVER=
export WEBDIR=
export doftp=

export vsdbhome=                 ;#script home, CHANGE TO YOUR SCRIPT HOLDER 
export srcgrads=$vsdbhome/grads
export NWPROD=
export PTMP=
export ndate=$NWPROD/util/exec/ndate
export GRADSBIN=                 	 ;#grads executable
export IMGCONVERT=                       ;#image magic converter 
export FC=                               ;#compiler
export FFLAG=                            ;#compiler options
export PYTHON=

## -- data and output directories
export vsdb_data=
export makemap=     		     ;#whether or not to make maps
export copymap=${copymap:-"NO"}      ;#copy maps to a central directory
export mapdir=
export scorecard=                    ;#create scorecard text files
export scoredir=                     ;#place to save scorecard out
scoretext=0; if [ $scorecard = "YES" ] ; then scoretext=1 ;fi
export archmon=${archmon:-"NO"}      ;#archive monthly means 
export murphy=${murphy:-"NO"}

## -- verification dates
export sdate=			#start of verification date
export edate=      		#end   of verification date
export vlength=			#forecast length in hours to be verified 
export fcycle=			#forecast cycles
y1=`echo $sdate |cut -c 1-4 `
m1=`echo $sdate |cut -c 5-6 `
d1=`echo $sdate |cut -c 7-8 `
y2=`echo $edate   |cut -c 1-4 `
m2=`echo $edate   |cut -c 5-6 `
d2=`echo $edate   |cut -c 7-8 `
ndays=`$srcgrads/days.sh -a $y2 $m2 $d2 - $y1 $m1 $d1`
export ndays=`expr $ndays + 1 ` #number of days back for verification
export xtick=`expr $ndays \/ 8 `

## -- verification parameters (dynamic ones)
export obsvlist=
export mdlist=
export reglist=
export rundir= 			     ;#splitted into observations and regions
export vhrlist=			     ;#verification hours for each day
export vtype=
export vnamlist=
export levlist=
       nlev=`echo $levlist |wc -w`
       levlist1=`echo $levlist | sed "s?P??g"`

##determine forecast output frequency required for verification
export nvhr=`echo $vhrlist |wc -w`   ;#number of verification hours
export fhout=`expr 24 \/ $nvhr `     ;#forecast output frequency
export nfcst=`expr $vlength \/ $fhout `

export FHOUR0=06

ncyc=`echo $fcycle | wc -w`             ;#count number of cycles

# WAFS: no f03 forecast, starting from f06
fhour=$FHOUR0
fhoursmap=""
fhours=""
while [ $fhour -le $vlength ] ; do
    fhour=`printf "%02d" $fhour`
    fhoursmap="fhour=$fhour|${fhoursmap}"
    fhours="$fhours $fhour"
    fhour=` expr $fhour + $fhout`
done
fhoursmap=`echo $fhoursmap | sed "s/|$//g"` # remove the last '|'

## remove missing data from all models to unify sample size, 0-->NO, 1-->Yes
export maskmiss=${maskmiss:-1}

#--------------------------------------------------------------------------
for obsv in $obsvlist ; do
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
for reg  in $reglist ; do
#--------------------------------------------------------------------------
  reg1=`echo $reg | sed "s?/??g"`

#--------------------------------------------------------------------------
for vnam in $vnamlist; do
#--------------------------------------------------------------------------
  vnam1=`echo $vnam | sed "s?/??g" |sed "s?_WV1?WV?g"`
  export exedir=${rundir}/${vnam1}
  if [ -s $exedir ]; then rm -rf $exedir ; fi
  mkdir -p $exedir ; cd $exedir || exit

# -- generate output names 
  outname1=${vnam1}_${reg1}_${sdate}${edate}
  yyyymm=`echo $edate |cut -c 1-6`
  if [ $ncyc -gt 1 ] ; then
   outmon=${vnam1}_${reg1}_${yyyymm}
  else
   outmon=${vnam1}_${reg1}_${fcycle}Z${yyyymm}
  fi

# -- search data for all models; write out binary data, create grads control file
  if [ $vnam = "WIND" ] ; then
   $srcgrads/gen_wind_pres.sh $vtype $vnam $reg "$levlist" $edate $ndays "${fcycle}" $vlength $fhout $outname1 $maskmiss "$mdlist" $obsv
   PLOTTYPES="3" # only plot type 3
  elif [ $vnam = "ICIP" ] ; then
   export fcstthrds="0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9"  #forecast threshold
   export nfcstthrds=`echo $fcstthrds | wc -w`
   export obsvthrds="0.2 0.4 0.6 0.8"                      #observation threshold
   export nobsvthrds=`echo $obsvthrds | wc -w`
   $srcgrads/gen_roc_pres.sh  $vtype $vnam $reg "$levlist" $edate $ndays "${fcycle}" $vlength $fhout $outname1 $maskmiss "$mdlist" $obsv
   PLOTTYPES="0" # no grads plotting. Plotting is done in gen_roc_pres.sh
  else
   $srcgrads/gen_scal_pres.sh $vtype $vnam $reg "$levlist" $edate $ndays "${fcycle}" $vlength $fhout $outname1 $maskmiss "$mdlist" $obsv
   PLOTTYPES="3" # only plot type 3
  fi

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
if [ $makemap = "YES" ] ; then
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# -- create grads scripts, allows up to 10 models 
nmd0=`echo $mdlist | wc -w`  ;#count number of models
nmd=`expr $nmd0 \* $ncyc `

# for display reason, change twind to gfs
mdlistc=`echo $mdlist | sed "s?twind?gfs?g"`

set -A mdname0  $mdlistc
set -A mdnamec0  `echo $mdlistc |tr "[a-z]" "[A-Z]" `
set -A cycname  $fcycle

n=0; mn=0
while [ $n -lt $nmd0 ] ; do
 m=0
 while [ $m -lt $ncyc ]; do
  if [ $ncyc -gt 1 ]; then
   mdname[mn]=${mdname0[n]}${cycname[m]}
   mdnamec[mn]=${mdnamec0[n]}${cycname[m]}
  else
   mdname[mn]=${mdname0[n]}
   mdnamec[mn]=${mdnamec0[n]}
  fi
  mn=`expr $mn + 1 `
  m=`expr $m + 1 `
 done
 n=`expr $n + 1 `
done

namedaily=${vnam1}_${reg1}

if [ $murphy = "YES" ] ; then
 varlist="rms bias pcor emd epv rsd msess"
else
 varlist="rms"
fi

#============================================
for var in $varlist ; do
#============================================

if [ $var = "rms" ];  then title="RMSE"         ;fi 
if [ $var = "msess" ];  then title="Murphy MSE Skill Score"         ;fi 
if [ $var = "bias" ]; then title="Bias"         ;fi 
if [ $var = "pcor" ];  then title="Pattern Correlation"         ;fi 
if [ $var = "emd" ];  then title="RMSE from Mean Difference"         ;fi 
if [ $var = "epv" ];  then title="RMSE from Pattern Variation"         ;fi 
if [ $var = "rsd" ];  then title="Fcst/Anal Ratio of Standard Deviation"     ;fi 


# Plot type selection:
#============================================
if [[ $PLOTTYPES =~ "1" ]] ; then
#============================================

# ----- PLOT TYPE 1:  maps of $var as a function of calendar day and pressure for each forecast time ----
cat >${var}p_${outname1}.gs <<EOF1 
'reinit'; 'set font 1'
'run $srcgrads/white.gs'
'open ${outname1}.ctl'
mdc.1=${mdnamec[0]}
if($nmd >1); mdc.2=${mdnamec[1]} ;endif
if($nmd >2); mdc.3=${mdnamec[2]} ;endif
if($nmd >3); mdc.4=${mdnamec[3]} ;endif
if($nmd >4); mdc.5=${mdnamec[4]} ;endif
if($nmd >5); mdc.6=${mdnamec[5]} ;endif
if($nmd >6); mdc.7=${mdnamec[6]} ;endif
if($nmd >7); mdc.8=${mdnamec[7]} ;endif
if($nmd >8); mdc.9=${mdnamec[8]} ;endif
if($nmd >9); mdc.10=${mdnamec[9]} ;endif


  nframe=$nmd
  xmin0=0.7;  xlen=3.5;  xgap=0.2
  ymax0=10.0; ygap=-0.1
               nframe2=1;  nframe3=2; ylen=-6.0
  if($nmd >2); nframe2=2;  nframe3=4; ylen=-4.2;endif
  if($nmd >4); nframe2=3;  nframe3=6; ylen=-2.8;endif
  if($nmd >6); nframe2=4;  nframe3=8; ylen=-2.1; endif
  if($nmd >8); nframe2=5;  nframe3=10; ylen=-1.7; endif

*------------------------
fhour0=6 ;*start from fcst06
fhour=fhour0
while ( fhour <= ${vlength} )
if ($fhoursmap)
*------------------------
  'c'
  fcstsave=fhour
  if(fhour < 10); fcstsave='0'%fcstsave;endif
  laty=(fhour-fhour0)/${fhout}+1
  'set x 1'       
  'set y '%laty
  'set t 1 $ndays' 
  'set z 1 $nlev' 


*--find maximum and minmum values
   cmax=-10000000.0; cmin=10000000.0
   i=1
*  while (i <= $nmd)
    'set gxout stat'
    'd ${var}(x='%i')'
    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>0 )
      if(zmax > cmax); cmax=zmax; endif
      if(zmin < cmin); cmin=zmin; endif
    endif
*  i=i+1
*  endwhile
   dist=cmax-cmin; cmin=cmin-0.1*dist; cmax=cmax+0.1*dist
   cmin=substr(cmin,1,8); cmax=substr(cmax,1,8)
   dist=cmax-cmin;  cint=0
   if( dist > 0.01 ); cint=10*substr((cmax-cmin)/100,1,4); endif
   if (cint = 0 & dist > 0.001 ); cint=substr((cmax-cmin)/10,1,4); endif
   if (cint = 0 & dist > 0.0001 ); cint=0.1*substr((cmax-cmin),1,4); endif
   if (cint = 0 & dist > 0.00001 ); cint=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cint = 0 & dist > 0.000001 ); cint=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cint = 0 & dist > 0.0000001 ); cint=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cint
    bb1=cmin; bb2=cmin+cint; bb3=bb2+cint; bb4=bb3+cint; bb5=bb4+cint; bb6=bb5+cint
    bb7=bb6+cint; bb8=bb7+cint; bb9=bb8+cint; bb10=bb9+cint; bb11=bb10+cint


*--find maximum and minmum values for difference map
   cmax=-10000000.0; cmin=10000000.0
   i=2
   if( $var = bias ); i=1 ;endif
   while (i <= $nmd)
    'set gxout stat'
    if( $var = bias )
     'd ${var}(x='%i')'
    else
     'd ${var}(x='%i')-${var}(x=1)'
    endif
    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>0 )
     if(zmax > cmax); cmax=zmax; endif
     if(zmin < cmin); cmin=zmin; endif
    endif
   i=i+1
   endwhile
   if ( cmax >= -cmin); 
     cmin=-cmax
   else
     cmax=-cmin
   endif
** dist=cmax-cmin; cmin=cmin; cmax=cmax+0.1*dist
   cmin=substr(cmin,1,8); cmax=substr(cmax,1,8); cintp=0
     if ( cmax > 0.005 ); cintp=10*substr(cmax/50,1,4); endif
     if (cintp = 0 & cmax > 0.0005 ); cintp=substr(cmax/5,1,4); endif
     if (cintp = 0 & cmax > 0.0001 ); cintp=0.2*substr(cmax,1,4); endif
     if (cintp = 0 & cmax > 0.00001 ); cintp=0.02*substr(cmax*10,1,4); endif
     if (cintp = 0 & cmax > 0.000001 ); cintp=0.002*substr(cmax*1000,1,4); endif
     if (cintp = 0 & cmax > 0.0000001 ); cintp=0.0002*substr(cmax*10000,1,4); endif
   cp1=cintp; cp2=cp1+cintp; cp3=cp2+cintp; cp4=cp3+cintp; cp5=cp4+cintp
              cp6=cp5+cintp; cp7=cp6+cintp; cp8=cp7+cintp; cp9=cp8+cintp
   cm1=-cp1 ; cm2=-cp2     ; cm3=-cp3     ; cm4=-cp4     ; cm5=-cp5     
              cm6=-cp6     ; cm7=-cp7     ; cm8=-cp8     ; cm9=-cp9     
   say 'cmin cmax cintm cintp 'cmin' 'cmax' 'cintm' 'cintp


  i=1
  while ( i <= nframe )
  'set gxout stat'  ;*count good data numbers
  'd ${var}(x='%i')'
  ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
  if ( b>0 )
    icx=1; if (i > nframe2); icx=2; endif
    if (i > nframe3); icx=3; endif
    if (i > nframe4); icx=4; endif
    xmin=xmin0+(icx-1)*(xlen+xgap)
    xmax=xmin+xlen
    icy=i; if (i > nframe2); icy=i-nframe2; endif
    if (i > nframe3); icy=i-nframe3; endif
    if (i > nframe4); icy=i-nframe4; endif
    ymax=ymax0+(icy-1)*(ylen+ygap)
    ymin=ymax+ylen
    titlx=xmin+0.15
    titly=ymax-0.3
    'set parea 'xmin' 'xmax' 'ymin' 'ymax

    'run $srcgrads/rgbset.gs'
    'set xlopts 1 4 0.0'
    'set ylopts 1 4 0.0'
      if($nmd <=2)
        'set xlopts 1 4 0.11'
        if(i=1);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >2 & $nmd <=4)
        if(i=2|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=2);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >4 & $nmd <=6)
        if(i=3|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=3);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >6 & $nmd <=8)
        if(i=4|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=4);'set ylopts 1 4 0.10';endif
      endif
      if($nmd >8)
        if(i=5|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=5);'set ylopts 1 4 0.09';endif
      endif
    'set clopts 1 4 0.09'
    'set grid on'
    'set zlog on'
    'set mproj off'

    'set gxout shaded'
    'set grads off'
    'set clevs   'cm5' 'cm4' 'cm3' 'cm2' 'cm1' 0 'cp1' 'cp2' 'cp3' 'cp4' 'cp5
    if ( $var = bias | $var = rms | $var = emd | $var = epv )
     'set rbcols 39    37    36   35    34    32 62   64    65   66     67   69'
    else
     'set rbcols 69    67    66   65    64    62 32   34    35   36     37   39'
    endif
    if(i=1 & $var != bias );'set clevs   'bb1' 'bb2' 'bb3' 'bb4' 'bb5' 'bb6' 'bb7' 'bb8' 'bb9' 'bb10' 'bb11 ;endif
    if(i=1 & $var = msess );'set clevs     -0.1  0    0.1   0.2   0.3   0.4   0.5  0.6    0.7   0.8    0.9  '  ;endif
    if(i=1 & $var != bias );'set rbcols 41   42    43    44    45   46  47  48    49   55     56   57';endif
*   'set ylevs 1000 925 850 700 500 400 300 250 200 150 100 50 20 10'              
    'set ylevs $levlist1'
    'set xlint $xtick'
    if(i=1 | $var = bias )
     'd ${var}(x='%i')'
    else
     'd ${var}(x='%i')- ${var}(x=1) '
    endif
*
    'set gxout contour'
    'set grads off'
    'set ccolor 1'
    'set clevs   'cm5' 'cm4' 'cm3' 'cm2' 'cm1' 0 'cp1' 'cp2' 'cp3' 'cp4' 'cp5
    if(i=1 | $var = bias );'set clevs   'bb1' 'bb2' 'bb3' 'bb4' 'bb5' 'bb6' 'bb7' 'bb8' 'bb9' 'bb10' 'bb11 ;endif
    if(i=1 & $var = msess );'set clevs     -0.1  0    0.1   0.2   0.3   0.4   0.5  0.6    0.7   0.8    0.9  '  ;endif
    'set clab on'
    if(i=1);'set clab forced';endif
    'set cstyle 3'
    'set xlint $xtick'
    if(i=1 | $var = bias );'d ${var}(x='%i')' ;endif
*   if(i>1);'d ${var}(x='%i')- ${var}(x=1) ';endif

    'set string 1 bl 7'
    'set strsiz 0.16 0.16'
    if(i=1 | $var = bias )
      'draw string 'titlx' 'titly' 'mdc.i 
    else
      'draw string 'titlx' 'titly' 'mdc.i '-' mdc.1
    endif
  endif
  i=i+1
  endwhile

  'set string 1 bc 6'
  'set strsiz 0.15 0.15'
  'draw string 4.5 10.45 ${vnam}: ${title}'
  'set strsiz 0.15 0.15'
  if ( $ncyc >1 )
   'draw string 4.5 10.20 ${reg}, Fcst fh'fcstsave
  else
   'draw string 4.5 10.20 ${reg} ${fcycle}Z, Fcst fh'fcstsave
  endif
  'set string 1 bc 5'
  'set strsiz 0.15 0.15'
  if($nmd >2)
    'run $srcgrads/cbarn.gs 0.95 0 4.5 0.25'
   else
    'run $srcgrads/cbarn.gs 0.95 0 4.5 2.90'
   endif

  'printim ${var}p_f'fcstsave'_${namedaily}.png x700 y700'
  'set vpage off'
*--------
endif
fhour=fhour+${fhout}
endwhile
*-------
'quit'
EOF1
$GRADSBIN/grads -bcp "run ${var}p_${outname1}.gs"

#============================================
elif [[ $PLOTTYPES =~ "2" ]] ; then
#============================================

# ----- PLOT TYPE 2:  maps of mean ${var} as a function of forecast time and pressure  ----
ndaysp1=`expr $ndays + 1`
fdaysp1=`expr $fdays + 1`
cat >${var}pmean_${outname1}.gs <<EOF1 
'reinit'; 'set font 1'
'run $srcgrads/white.gs'
'open ${outname1}.ctl'
mdc.1=${mdnamec[0]}
if($nmd >1); mdc.2=${mdnamec[1]} ;endif
if($nmd >2); mdc.3=${mdnamec[2]} ;endif
if($nmd >3); mdc.4=${mdnamec[3]} ;endif
if($nmd >4); mdc.5=${mdnamec[4]} ;endif
if($nmd >5); mdc.6=${mdnamec[5]} ;endif
if($nmd >6); mdc.7=${mdnamec[6]} ;endif
if($nmd >7); mdc.8=${mdnamec[7]} ;endif
if($nmd >8); mdc.9=${mdnamec[8]} ;endif
if($nmd >9); mdc.10=${mdnamec[9]} ;endif

  nframe=$nmd
  xmin0=0.7;  xlen=3.5;  xgap=0.2
  ymax0=10.0; ygap=-0.1
               nframe2=1;  nframe3=2; ylen=-6.0
  if($nmd >2); nframe2=2;  nframe3=4; ylen=-4.2;endif
  if($nmd >4); nframe2=3;  nframe3=6; ylen=-2.8;endif
  if($nmd >6); nframe2=4;  nframe3=8; ylen=-2.1; endif
  if($nmd >8); nframe2=5;  nframe3=10; ylen=-1.7; endif


  'c'
  'set x 1'
  'set t $ndaysp1'
  'set y 1 ${nfcst}'
  'set z 1 $nlev' 

*--find maximum and minmum values for first total field map
   cmax=-10000000.0; cmin=10000000.0
   i=1
*  while (i <= $nmd)
    'set gxout stat'
    'd ${var}(x='%i')'
    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    if(zmax > cmax); cmax=zmax; endif
    if(zmin < cmin); cmin=zmin; endif
*  i=i+1
*  endwhile
   dist=cmax-cmin; cmin=cmin-0.1*dist; cmax=cmax+0.1*dist
   cmin=substr(cmin,1,8); cmax=substr(cmax,1,8)
   dist=cmax-cmin; cint=0
   if ( dist > 0.01 ); cint=10*substr((cmax-cmin)/100,1,4); endif
   if (cint = 0 & dist > 0.001 ); cint=substr((cmax-cmin)/10,1,4); endif
   if (cint = 0 & dist > 0.0001 ); cint=0.1*substr((cmax-cmin),1,4); endif
   if (cint = 0 & dist > 0.00001 ); cint=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cint = 0 & dist > 0.000001 ); cint=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cint = 0 & dist > 0.0000001 ); cint=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cint
    bb1=cmin; bb2=cmin+cint; bb3=bb2+cint; bb4=bb3+cint; bb5=bb4+cint; bb6=bb5+cint
    bb7=bb6+cint; bb8=bb7+cint; bb9=bb8+cint; bb10=bb9+cint; bb11=bb10+cint

*--find maximum and minmum values for difference map
   cmax=-10000000.0; cmin=10000000.0
   i=2
   if( $var = bias ); i=1 ;endif
   while (i <= $nmd)
    'set gxout stat'
    if( $var = bias ) 
     'd ${var}(x='%i')'
    else
     'd ${var}(x='%i')-${var}(x=1)'
    endif
    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>0 )
     if(zmax > cmax); cmax=zmax; endif
     if(zmin < cmin); cmin=zmin; endif
    endif
   i=i+1
   endwhile
   if ( cmax >= -cmin); 
     cmin=-cmax
   else
     cmax=-cmin
   endif
** dist=cmax-cmin; cmin=cmin; cmax=cmax+0.1*dist
   cmin=substr(cmin,1,8); cmax=substr(cmax,1,8); cintp=0
     if ( cmax > 0.005 ); cintp=10*substr(cmax/50,1,4); endif
     if (cintp = 0 & cmax > 0.0005 ); cintp=substr(cmax/5,1,4); endif
     if (cintp = 0 & cmax > 0.0001 ); cintp=0.2*substr(cmax,1,4); endif
     if (cintp = 0 & cmax > 0.00001 ); cintp=0.02*substr(cmax*10,1,4); endif
     if (cintp = 0 & cmax > 0.000001 ); cintp=0.002*substr(cmax*1000,1,4); endif
     if (cintp = 0 & cmax > 0.0000001 ); cintp=0.0002*substr(cmax*10000,1,4); endif
   cp1=cintp; cp2=cp1+cintp; cp3=cp2+cintp; cp4=cp3+cintp; cp5=cp4+cintp
              cp6=cp5+cintp; cp7=cp6+cintp; cp8=cp7+cintp; cp9=cp8+cintp
   cm1=-cp1 ; cm2=-cp2     ; cm3=-cp3     ; cm4=-cp4     ; cm5=-cp5     
              cm6=-cp6     ; cm7=-cp7     ; cm8=-cp8     ; cm9=-cp9     
   say 'cmin cmax cintm cintp 'cmin' 'cmax' 'cintm' 'cintp


  i=1
  while ( i <= nframe )
  'set gxout stat'  ;*count good data numbers
  'd ${var}(x='%i')'
  ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
  if ( b>0 )
    icx=1; if (i > nframe2); icx=2; endif
    if (i > nframe3); icx=3; endif
    if (i > nframe4); icx=4; endif
    xmin=xmin0+(icx-1)*(xlen+xgap)
    xmax=xmin+xlen
    icy=i; if (i > nframe2); icy=i-nframe2; endif
    if (i > nframe3); icy=i-nframe3; endif
    if (i > nframe4); icy=i-nframe4; endif
    ymax=ymax0+(icy-1)*(ylen+ygap)
    ymin=ymax+ylen
    titlx=xmin+0.15
    titly=ymax-0.3
    'set parea 'xmin' 'xmax' 'ymin' 'ymax

    'run $srcgrads/rgbset.gs'
    'set xlopts 1 4 0.0'
    'set ylopts 1 4 0.0'
      if($nmd <=2)
        'set xlopts 1 4 0.11'
        if(i=1);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >2 & $nmd <=4)
        if(i=2|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=2);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >4 & $nmd <=6)
        if(i=3|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=3);'set ylopts 1 4 0.11';endif
      endif
      if($nmd >6 & $nmd <=8)
        if(i=4|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=4);'set ylopts 1 4 0.10';endif
      endif
      if($nmd >8)
        if(i=5|i=$nmd);'set xlopts 1 4 0.11';endif
        if(i<=5);'set ylopts 1 4 0.09';endif
      endif
    'set clopts 1 4 0.09'
    'set grid on'
    'set zlog on'
    'set mproj off'

    'set gxout shaded'
    'set grads off'
    'set clevs   'cm5' 'cm4' 'cm3' 'cm2' 'cm1' 0 'cp1' 'cp2' 'cp3' 'cp4' 'cp5
    if ( $var = bias | $var = rms | $var = emd | $var = epv )
     'set rbcols 39    37    36   35    34    32 62   64    65   66     67   69'
    else
     'set rbcols 69    67    66   65    64    62 32   34    35   36     37   39'
    endif
    if(i=1 & $var != bias );'set clevs   'bb1' 'bb2' 'bb3' 'bb4' 'bb5' 'bb6' 'bb7' 'bb8' 'bb9' 'bb10' 'bb11 ;endif
    if(i=1 & $var = msess );'set clevs     -0.1  0    0.1   0.2   0.3   0.4   0.5  0.6    0.7   0.8    0.9  '  ;endif
    if(i=1 & $var != bias );'set rbcols 41   42    43    44    45   46  47  48    49   55     56   57';endif
*   'set ylevs 1000 925 850 700 500 400 300 250 200 150 100 50 20 10'              
*   'set ylevs 1000 850 700 500 400 300 200 100 50 20 10'              
    'set ylevs $levlist1'
    'set xlint 48'
    if(i=1 | $var = bias )
     'd ${var}(x='%i')'
    else
     'd ${var}(x='%i')-${var}(x=1)'
    endif
*
    'set gxout contour'
    'set grads off'
    'set ccolor 1'
    'set clevs   'cm5' 'cm4' 'cm3' 'cm2' 'cm1' 0 'cp1' 'cp2' 'cp3' 'cp4' 'cp5
    if(i=1 & $var != bias );'set clevs   'bb1' 'bb2' 'bb3' 'bb4' 'bb5' 'bb6' 'bb7' 'bb8' 'bb9' 'bb10' 'bb11 ;endif
    if(i=1 & $var = msess );'set clevs     -0.1  0    0.1   0.2   0.3   0.4   0.5  0.6    0.7   0.8    0.9  '  ;endif
    'set clab on'
    if(i=1);'set clab forced';endif
    'set cstyle 3'
    if(i=1 | $var = bias )
     'd ${var}(x='%i')'
    else
     'd ${var}(x='%i')-${var}(x=1)'
    endif

    'set string 1 bl 7'
    'set strsiz 0.16 0.16'
    if(i=1 | $var = bias )
     'draw string 'titlx' 'titly' 'mdc.i 
    else
     'draw string 'titlx' 'titly' 'mdc.i '-' mdc.1
    endif
  endif
  i=i+1
  endwhile

  'set string 1 bc 6'
  'set strsiz 0.15 0.15'
  'draw string 4.5 10.45 ${vnam}: ${title}'
  'set strsiz 0.15 0.15'
  if ( $ncyc >1 )
   'draw string 4.5 10.20 $sdate-$edate Mean, ${reg}'
  else
   'draw string 4.5 10.20 $sdate-$edate Mean, ${reg} ${fcycle}Z'
  endif
  'set string 1 bc 4'
  'set strsiz 0.14 0.14'
  'set strsiz 0.15 0.15'
  if($nmd >2)
    'draw string 4.8 0.7 Forecast Hour'
    'run $srcgrads/cbarn.gs 0.95 0 4.5 0.25'
   else
    'draw string 4.3 3.5 Forecast Hour'
    'run $srcgrads/cbarn.gs 0.95 0 4.5 2.90'
   endif

  'printim ${var}pmean_${namedaily}.png x700 y700'
  'set vpage off'
'quit'
EOF1
$GRADSBIN/grads -bcp "run ${var}pmean_${outname1}.gs"

#============================================
fi #  $PLOTTYPES
#============================================


#-------------------------------------------------------------------
#-------------------------------------------------------------------
#  The following are time series (line plots) for a specific forecast 
#  hour as a function of calendar day

#vlisttmp="$levlist"
vlisttmp="$levlist"
if [ $vnam = "O3" ]; then vlisttmp="P100 P70 P50 P30 P20 P10" ; fi

for lev  in $vlisttmp  ; do
  namedaily1=${vnam1}_${lev}_${reg1}
  levp=`echo $lev | sed "s?P??g"`
#-------------------------------------------------------------------


# choose 00z 12z average
#============================================
if [[ $PLOTTYPES =~ "3" ]] ; then # (inside levels)
#============================================

# ----- PLOT TYPE 3:  time series of ${var} Errors----
cat >${var}_${outname1}${lev}.gs <<EOF1 
'reinit'; 'set font 1'
'open ${outname1}.ctl'
mdc.1=${mdnamec[0]}
if($nmd >1); mdc.2=${mdnamec[1]} ;endif
if($nmd >2); mdc.3=${mdnamec[2]} ;endif
if($nmd >3); mdc.4=${mdnamec[3]} ;endif
if($nmd >4); mdc.5=${mdnamec[4]} ;endif
if($nmd >5); mdc.6=${mdnamec[5]} ;endif
if($nmd >6); mdc.7=${mdnamec[6]} ;endif
if($nmd >7); mdc.8=${mdnamec[7]} ;endif
if($nmd >8); mdc.9=${mdnamec[8]} ;endif
if($nmd >9); mdc.10=${mdnamec[9]} ;endif

mdl.1=${mdname0[0]}
if($nmd0 >1); mdl.2=${mdname0[1]} ;endif
if($nmd0 >2); mdl.3=${mdname0[2]} ;endif
if($nmd0 >3); mdl.4=${mdname0[3]} ;endif
if($nmd0 >4); mdl.5=${mdname0[4]} ;endif
if($nmd0 >5); mdl.6=${mdname0[5]} ;endif
if($nmd0 >6); mdl.7=${mdname0[6]} ;endif
if($nmd0 >7); mdl.8=${mdname0[7]} ;endif
if($nmd0 >8); mdl.9=${mdname0[8]} ;endif
if($nmd0 >9); mdl.10=${mdname0[9]} ;endif
 

*-- define line styles and model names 
  cst.1=1; cst.2=5; cst.3=3; cst.4=5; cst.5=5; cst.6=3; cst.7=5; cst.8=5; cst.9=5; cst.10=5
  cth.1=9; cth.2=9; cth.3=4; cth.4=1; cth.5=4; cth.6=1; cth.7=1; cth.8=1; cth.9=1; cth.10=1
  cma.1=0; cma.2=8; cma.3=6; cma.4=1; cma.5=2; cma.6=4; cma.7=7; cma.8=3; cma.9=8; cma.10=5
  cco.1=1; cco.2=2; cco.3=3; cco.4=4; cco.5=8; cco.6=15; cco.7=9; cco.8=5; cco.9=6; cco.10=7

*------------------------
fhour0=6 ;*start from fcst06
fhour=fhour0
while ( fhour <= ${vlength} )
if ($fhoursmap)
*------------------------
  'c'
  fcstsave=fhour
  if(fhour < 10); fcstsave='0'%fcstsave;endif
  laty=(fhour-fhour0)/${fhout}+1
  'set x 1'
  'set t 1 $ndays' 
  'set y '%laty 
  'set lev $levp '

  xwd=7.0; ywd=4.0; yy=ywd/17
  xmin=1.0; xmax=xmin+xwd; ymin=6.0; ymax=ymin+ywd
  xt=xmin+0.3; xtm=xt+0.25; xt1=xt+0.5; xt2=xt1+0.1; yt=ymin+0.36*ywd ;*for legend  
  zxt=xt2+3.0; zxtm=zxt+0.25; zxt1=zxt+0.5; zxt2=zxt1+0.1; zyt=ymin+0.36*ywd
  titlx=xmin+0.5*xwd;  titly=ymax+0.35                  ;*for tytle
  titlx2=xmin+0.5*xwd;  titly2=ymax+0.10                  ;*for tytle
  xlabx=xmin+0.5*xwd;  xlaby=ymin-0.60
  'set parea 'xmin' 'xmax' 'ymin' 'ymax

*--find maximum and minmum values
   cmax=-10000000.0; cmin=10000000.0
   i=1
   while (i <= $nmd0)
    'set gxout stat'
*    'd ${var}(x='%i')'
    ii=$ncyc*(i-1)+1
    'd (rms(x='%ii')+rms(x='%ii+2'))'

    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>0 )
     if(zmax > cmax); cmax=zmax; endif
     if(zmin < cmin); cmin=zmin; endif
    endif
   i=i+1
   endwhile
   dist=cmax-cmin; cmin=cmin-1.7*dist; cmax=1.2*cmax
   cmin=substr(cmin,1,10); cmax=substr(cmax,1,10)
   dist=cmax-cmin; cint=0
   if ( dist > 0.01 ); cint=10*substr((cmax-cmin)/100,1,4); endif
   if (cint = 0 & dist > 0.001 ); cint=substr((cmax-cmin)/10,1,4); endif
   if (cint = 0 & dist > 0.0001 ); cint=0.1*substr((cmax-cmin),1,4); endif
   if (cint = 0 & dist > 0.00001 ); cint=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cint = 0 & dist > 0.000001 ); cint=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cint = 0 & dist > 0.0000001 ); cint=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cint

   i=1
   while (i <= $nmd0)
    'set gxout stat'  ;* first compute means and count good data numbers
*    'd ${var}(x='%i')'
    ii=$ncyc*(i-1)+1
    'd (rms(x='%ii')+rms(x='%ii+2'))'
    ln=sublin(result,11); wd=subwrd(ln,2); a=substr(wd,1,5);sc.i=subwrd(ln,2)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if ( b>0 )
      if( i <=5);
        'set strsiz 0.13 0.13'; yt=yt-yy
        'set line 'cco.i' 'cst.i' 11'; 'draw line 'xt' 'yt' 'xt1' 'yt
*        'set string 'cco.i' bl 6';     'draw string 'xt2' 'yt' 'mdc.i'  ' a'  'b
        'set string 'cco.i' bl 6';     'draw string 'xt2' 'yt' 'mdl.i'  ' a'  'b
        'draw mark 'cma.i' 'xtm' 'yt' 0.10'
      else
        'set strsiz 0.13 0.13'; zyt=zyt-yy
        'set line 'cco.i' 'cst.i' 11'; 'draw line 'zxt' 'zyt' 'zxt1' 'zyt
*        'set string 'cco.i' bl 6';     'draw string 'zxt2' 'zyt' 'mdc.i'  ' a'  'b
        'set string 'cco.i' bl 6';     'draw string 'zxt2' 'zyt' 'mdl.i'  ' a'  'b
        'draw mark 'cma.i' 'zxtm' 'zyt' 0.10'
      endif

      'set gxout line'
      'set display color white'; 'set missconn on';     'set grads off'; 'set grid on'
      'set xlopts 1 6 0.14';     'set ylopts 1 6 0.14'; 'set clopts 1 6 0.0'
      'set vrange 'cmin' 'cmax; 'set ylint 'cint
      'set xlint $xtick'
      'set cstyle 'cst.i; 'set cthick 'cth.i; 'set cmark 'cma.i; 'set ccolor 'cco.i
*      'd ${var}(x='%i')'
    'd (rms(x='%ii')+rms(x='%ii+2'))'
     endif
* Create verification scorecard text files
     if ( $scoretext = 1 ) 
       '${srcgrads}/fprintf.gs 'sc.i' score_${var}_${namedaily1}_'mdc.i'_f'fcstsave'.txt %-7.6f'
     endif
   i=i+1
   endwhile

  'set string 1 bc 7'
  'set strsiz 0.14 0.14'
  'draw string 'titlx' 'titly' ${vnam}: ${title} '
  'set strsiz 0.14 0.14'
  if ( $ncyc >1 )
   'draw string 'titlx2' 'titly2' ${lev} ${reg}, fh'fcstsave
  else
   'draw string 'titlx2' 'titly2' ${lev} ${reg} ${fcycle}Z, fh'fcstsave
  endif
  'set strsiz 0.15 0.15'
  'draw string 'xlabx' 'xlaby' Verification Date'

  'printim ${var}_f'fcstsave'_${namedaily1}.png x800 y800'
  'set vpage off'
*--------
endif
fhour=fhour+${fhout}
endwhile
*-------
'quit'
EOF1
$GRADSBIN/grads -bcp "run ${var}_${outname1}${lev}.gs"

#============================================
elif [[ $PLOTTYPES =~ "4" ]] ; then
#============================================

# ----- PLOT TYPE 4:  mean ${var} error growth curve over $ndays days----
ndaysp1=`expr $ndays + 1`
fdaysp1=`expr $fdays + 1`
cat >${var}dieoff_${outname1}${lev}.gs <<EOF1 
'reinit'; 'set font 1'
'open ${outname1}.ctl'
mdc.1=${mdnamec[0]}
if($nmd >1); mdc.2=${mdnamec[1]} ;endif
if($nmd >2); mdc.3=${mdnamec[2]} ;endif
if($nmd >3); mdc.4=${mdnamec[3]} ;endif
if($nmd >4); mdc.5=${mdnamec[4]} ;endif
if($nmd >5); mdc.6=${mdnamec[5]} ;endif
if($nmd >6); mdc.7=${mdnamec[6]} ;endif
if($nmd >7); mdc.8=${mdnamec[7]} ;endif
if($nmd >8); mdc.9=${mdnamec[8]} ;endif
if($nmd >9); mdc.10=${mdnamec[9]} ;endif

*-- define line styles and model names 
  cst.1=1; cst.2=1; cst.3=1; cst.4=1; cst.5=1; cst.6=1; cst.7=1; cst.8=1; cst.9=1; cst.10=1
  cth.1=12; cth.2=12; cth.3=9; cth.4=9; cth.5=9; cth.6=9; cth.7=9; cth.8=9; cth.9=9; cth.10=9
  cma.1=2; cma.2=0; cma.3=0; cma.4=0; cma.5=0; cma.6=0; cma.7=0; cma.8=0; cma.9=0; cma.10=0
  cco.1=1; cco.2=2; cco.3=3; cco.4=4; cco.5=8; cco.6=9; cco.7=5; cco.8=6; cco.9=7; cco.10=15
  bar.1=30; bar.2=40; bar.3=50; bar.4=60; bar.5=70; bar.6=80; bar.7=90; bar.8=92; bar.9=94; bar.10=96

  'set x 1'
  'set lev $levp '
  'set t $ndaysp1' 
  'set y 1 ${nfcst}'
  xwd=7.0; ywd=5.0; yy=ywd/17
  xmin=0.8; xmax=xmin+xwd; ymin=5.0; ymax=ymin+ywd
  xt=xmin+0.3; xt1=xt+0.5; xt2=xt1+0.1; yt=ymax;*for legend  
  titlx=xmin+0.5*xwd;  titly=ymax+0.35                  ;*for tytle
  titlx2=xmin+0.5*xwd;  titly2=ymax+0.10                  ;*for tytle
  xlabx=xmin+0.5*xwd;  xlaby=ymin-0.60
  'set parea 'xmin' 'xmax' 'ymin' 'ymax

*--find maximum and minmum values
   cmax=-10000000.0; cmin=10000000.0
   i=1
   while (i <= $nmd)
    'set gxout stat'
    'd ${var}(x='%i')'
    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>1 )
     if(zmax > cmax); cmax=zmax; endif
     if(zmin < cmin); cmin=zmin; endif
    endif
   i=i+1
   endwhile
   if ( $var = pcor | $var = rsd | $var = bias | $var = msess) 
     cmin=substr(cmin,1,10) 
   else
     cmin=0
   endif
   cmax=substr(cmax,1,10)
   dist=cmax-cmin; cint=0
   if ( dist > 0.01 ); cint=10*substr((cmax-cmin)/100,1,4); endif
   if (cint = 0 & dist > 0.001 ); cint=substr((cmax-cmin)/10,1,4); endif
   if (cint = 0 & dist > 0.0001 ); cint=0.1*substr((cmax-cmin),1,4); endif
   if (cint = 0 & dist > 0.00001 ); cint=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cint = 0 & dist > 0.000001 ); cint=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cint = 0 & dist > 0.0000001 ); cint=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cint

   i=1
   while (i <= $nmd)
    'set gxout stat'      ;* first compute means and count good data numbers
    'd bincor(x='%i')'    ;* number of records
    ln=sublin(result,11); wd=subwrd(ln,2); a=substr(wd,1,3)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if ( a>0 & b>1 )
      'set strsiz 0.13 0.13'; yt=yt-yy
      'set line 'cco.i' 'cst.i' 11'; 'draw line 'xt' 'yt' 'xt1' 'yt
      'set string 'cco.i' bl 6';     'draw string 'xt2' 'yt' 'mdc.i'  ' a

      'set gxout line'
      'set mproj off'
      'set display color white'; 'set missconn on';     'set grads off'; 'set grid on'
      'set xlopts 1 6 0';     'set ylopts 1 6 0.14'; 'set clopts 1 6 0.0'
      'set vrange 'cmin ' 'cmax; 'set ylint 'cint; 'set xlint 48'
      'set cstyle 'cst.i; 'set cthick 'cth.i; 'set cmark 'cma.i; 'set ccolor 'cco.i
      'd ${var}(x='%i')'
     endif
   i=i+1
   endwhile

  'set string 1 bc 6'
  'set strsiz 0.13 0.13'
  'draw string 'titlx' 'titly' ${vnam}: ${title}'
  'set strsiz 0.13 0.13'
  if ( $ncyc >1 )
   'draw string 'titlx2' 'titly2' ${lev} ${reg}, $sdate-$edate Mean'
  else
   'draw string 'titlx2' 'titly2' ${lev} ${reg} ${fcycle}Z, $sdate-$edate Mean'
  endif

*---------------------------------------------------------
* plot difference between others and the first
  ymin=ymin-4; ymax=ymin+4
  'set parea 'xmin' 'xmax' 'ymin' 'ymax
  xlabx=xmin+0.45*xwd;  xlaby=ymin-0.60
                                                                                                                    
*--find maximum and minmum values to determine y-axis labels
 cmax=-999.0; cmin=999.0
 i=2
 while (i <= $nmd)
   'set gxout stat'  ;* find good data records
   'd bincor(x='%i')'     
   ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
   if ( b>1 )
     'set gxout stat'
     'd ${var}(x='%i')-${var}(x=1)'
     range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
     ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
     if ( b>0 )
      if(zmax > cmax); cmax=zmax; endif
      if(zmin < cmin); cmin=zmin; endif
     endif
   endif
 i=i+1
 endwhile
 if ( cmax < 0); cmax=0;endif
 if ( cmin > 0); cmin=0;endif
 cmin=substr(cmin,1,10); cmax=substr(cmax,1,10)
   dist=cmax-cmin; cintp=0
   if ( dist > 0.01 ); cintp=10*substr((cmax-cmin)/100,1,4); endif
   if (cintp = 0 & dist > 0.001 ); cintp=substr((cmax-cmin)/10,1,4); endif
   if (cintp = 0 & dist > 0.0001 ); cintp=0.1*substr((cmax-cmin),1,4); endif
   if (cintp = 0 & dist > 0.00001 ); cintp=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cintp = 0 & dist > 0.000001 ); cintp=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cintp = 0 & dist > 0.0000001 ); cintp=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cintp

                                                                                                                    
*---------------------------------------------------------
* compute standard deviation of the difference between the
* first and each of the rest models for each forecast hour

 i=2
 while (i <= $nmd)
  'set gxout stat'  ;* find good data records
  'd bincor(x='%i')'     
  ln=sublin(result,11); wd=subwrd(ln,2); a=substr(wd,1,3)
  ln=sublin(result,7); ct=subwrd(ln,8)
  if ( a>0 )
    'define acdm=ave(${var}(x='%i')-${var}(x=1),t=1,t=$ndays)'
**       standard deviation of difference
    'define std=sqrt(ave((${var}(x='%i')-${var}(x=1)-acdm)*(${var}(x='%i')-${var}(x=1)-acdm),t=1,t=$ndays))'
    'define nsz=bincor(x='%i')'
**      Null Hypothesis: mean(AC1-AC2)=0, AC1-AC2 follows normal distribution.
**      plot the 5% conf interval of difference of means : F*SD/sqrt(N-1),
**      F=1.96 for infinite samples, F=2.0 for nsz=60, F=2.042 for nsz=30, F=2.228 for nsz=10
    if(nsz>=80);            'define intvl=1.960*std/sqrt(nsz-1)'  ;endif
    if(nsz>=40 & nsz <80);  'define intvl=2.000*std/sqrt(nsz-1)'  ;endif
    if(nsz>=20 & nsz <40);  'define intvl=2.042*std/sqrt(nsz-1)'  ;endif
    if(nsz<20);             'define intvl=2.228*std/sqrt(nsz-1)'  ;endif

     'set gxout bar'
     'set bargap 'bar.i
     'set baropts outline'
     'set ccolor 'cco.i
     'set cstyle 1'; 'set cthick 3'; 'set cmark 0'
     'set mproj off'
     'set display color white'; 'set grads off'; 'set grid on'
     'set xlopts 1 6 0.0';     'set ylopts 1 6 0.0'; 'set clopts 1 6 0.0'
     'set vrange 'cmin' 'cmax; 'set ylint 'cintp; 'set xlint 48'
     'd -intvl;intvl'
**add missing bars when intvl is larger than cmax
    'set ccolor 'cco.i
    'define xa=maskout(intvl*0+0.999*'cmin',intvl+'cmin')'
    'define xb=maskout(intvl*0+0.999*'cmax',intvl-'cmax')'
    'set datawarn off'
    'd xa;xb'
  endif

** Create verification scorecard text files
  if ( $scoretext = 1 )
   'set gxout print'
   'set prnopts %10.4e 'ct
   'd intvl'
   ln=sublin(result,2)
   n=2
   while (n<=ct)
     tv.n=subwrd(ln,n)
     say tv.n
     '${srcgrads}/fprintf.gs 'tv.n' score_${var}_conflimit_'${namedaily1}'_'mdc.i'_day'n-1'.txt %-7.6f'
    n=n+1
   endwhile
  endif
 i=i+1
 endwhile


 i=1
 while (i <= $nmd)
   'set gxout stat'  ;* find good data records
   'd bincor(x='%i')'     
   ln=sublin(result,11); wd=subwrd(ln,2); a=substr(wd,1,3)
   if ( a>0 )
     'set gxout line'
     'set mproj off'
     'set display color white'; 'set missconn on';     'set grads off'; 'set grid on'
     'set xlopts 1 6 0.14';     'set ylopts 1 6 0.14'; 'set clopts 1 6 0.0'
     'set vrange 'cmin' 'cmax; 'set ylint 'cintp; 'set xlint 48'
     'set cstyle 'cst.i; 'set cthick 'cth.i; 'set cmark 'cma.i; 'set ccolor 'cco.i
     if(i=1); 'set cstyle 1'; 'set cthick 1'; 'set cmark 0'; 'set ccolor 1'; endif
     'd ${var}(x='%i')-${var}(x=1)'
   endif
 i=i+1
 endwhile
                                                                                                                    
 'set strsiz 0.14 0.14'
 'draw string 'xlabx' 'xlaby' Forecast Hour'
 'set string 1 bl 6'
 'set strsiz 0.14 0.14'
 'draw string 'xmin+0.2' 'ymax-0.4' Difference w.r.t. 'mdc.1
 'set string 1 bl 3'
 'set strsiz 0.11 0.11'
 if( $nmd > 1)
  'draw string 'xmin+0.1' 'ymin+0.3' ${var} differences outside of outline bars '
  'draw string 'xmin+0.1' 'ymin+0.1' are significant at the 95% confidence level'
 endif
*---------------------------------------------------------


 'printim ${var}dieoff_${namedaily1}.png x700 y700'
 'set vpage off'
'quit'
EOF1
$GRADSBIN/grads -bcp "run ${var}dieoff_${outname1}${lev}.gs"

#============================================
elif [[ $PLOTTYPES =~ "5" ]] ; then
#============================================

nfcstthrds=$(( nfcstthrds - 1 ))

# ----- PLOT TYPE 5:  mean ${var} error growth curve over $ndays days----
ndaysp1=`expr $ndays + 1`
fdaysp1=`expr $fdays + 1`
cat >${var}roc_${outname1}${lev}.gs <<EOF1 
'reinit'; 'set font 1'
'open ${outname1}.ctl'
mdc.1=${mdnamec[0]}
if($nmd >1); mdc.2=${mdnamec[1]} ;endif
if($nmd >2); mdc.3=${mdnamec[2]} ;endif
if($nmd >3); mdc.4=${mdnamec[3]} ;endif
if($nmd >4); mdc.5=${mdnamec[4]} ;endif
if($nmd >5); mdc.6=${mdnamec[5]} ;endif
if($nmd >6); mdc.7=${mdnamec[6]} ;endif
if($nmd >7); mdc.8=${mdnamec[7]} ;endif
if($nmd >8); mdc.9=${mdnamec[8]} ;endif
if($nmd >9); mdc.10=${mdnamec[9]} ;endif

mdl.1=${mdname0[0]}
if($nmd0 >1); mdl.2=${mdname0[1]} ;endif
if($nmd0 >2); mdl.3=${mdname0[2]} ;endif
if($nmd0 >3); mdl.4=${mdname0[3]} ;endif
if($nmd0 >4); mdl.5=${mdname0[4]} ;endif
if($nmd0 >5); mdl.6=${mdname0[5]} ;endif
if($nmd0 >6); mdl.7=${mdname0[6]} ;endif
if($nmd0 >7); mdl.8=${mdname0[7]} ;endif
if($nmd0 >8); mdl.9=${mdname0[8]} ;endif
if($nmd0 >9); mdl.10=${mdname0[9]} ;endif
 

*-- define line styles and model names 
  cst.1=1; cst.2=5; cst.3=3; cst.4=5; cst.5=5; cst.6=3; cst.7=5; cst.8=5; cst.9=5; cst.10=5
  cth.1=9; cth.2=9; cth.3=4; cth.4=1; cth.5=4; cth.6=1; cth.7=1; cth.8=1; cth.9=1; cth.10=1
  cma.1=0; cma.2=8; cma.3=6; cma.4=1; cma.5=2; cma.6=4; cma.7=7; cma.8=3; cma.9=8; cma.10=5
  cco.1=1; cco.2=2; cco.3=3; cco.4=4; cco.5=8; cco.6=15; cco.7=9; cco.8=5; cco.9=6; cco.10=7

*------------------------
fhour0=6 ;*start from fcst06
fhour=fhour0
while ( fhour <= ${vlength} )
if ($fhoursmap)
*------------------------
  'c'
  fcstsave=fhour
  if(fhour < 10); fcstsave='0'%fcstsave;endif
  laty=(fhour-fhour0)/${fhout}+1
  'set x 1'
  'set t 1 $nfcstthrds' 
  'set y '%laty 
  'set lev $levp '

  xwd=7.0; ywd=4.0; yy=ywd/17
  xmin=1.0; xmax=xmin+xwd; ymin=6.0; ymax=ymin+ywd
  xt=xmin+0.3; xtm=xt+0.25; xt1=xt+0.5; xt2=xt1+0.1; yt=ymin+0.36*ywd ;*for legend  
  zxt=xt2+3.0; zxtm=zxt+0.25; zxt1=zxt+0.5; zxt2=zxt1+0.1; zyt=ymin+0.36*ywd
  titlx=xmin+0.5*xwd;  titly=ymax+0.35                  ;*for tytle
  titlx2=xmin+0.5*xwd;  titly2=ymax+0.10                  ;*for tytle
  xlabx=xmin+0.5*xwd;  xlaby=ymin-0.60
  'set parea 'xmin' 'xmax' 'ymin' 'ymax

*--find maximum and minmum values
   cmax=-10000000.0; cmin=10000000.0
   i=1
   while (i <= $nmd0)
    'set gxout stat'
*    'd ${var}(x='%i')'
    ii=$ncyc*(i-1)+1
    'd (rms(x='%ii')+rms(x='%ii+2'))'

    range=sublin(result,9); zmin=subwrd(range,5); zmax=subwrd(range,6)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if( b>0 )
     if(zmax > cmax); cmax=zmax; endif
     if(zmin < cmin); cmin=zmin; endif
    endif
   i=i+1
   endwhile
   dist=cmax-cmin; cmin=cmin-1.7*dist; cmax=1.2*cmax
   cmin=substr(cmin,1,10); cmax=substr(cmax,1,10)
   dist=cmax-cmin; cint=0
   if ( dist > 0.01 ); cint=10*substr((cmax-cmin)/100,1,4); endif
   if (cint = 0 & dist > 0.001 ); cint=substr((cmax-cmin)/10,1,4); endif
   if (cint = 0 & dist > 0.0001 ); cint=0.1*substr((cmax-cmin),1,4); endif
   if (cint = 0 & dist > 0.00001 ); cint=0.01*substr((cmax-cmin)*10,1,4); endif
   if (cint = 0 & dist > 0.000001 ); cint=0.001*substr((cmax-cmin)*100,1,4); endif
   if (cint = 0 & dist > 0.0000001 ); cint=0.0001*substr((cmax-cmin)*1000,1,4); endif
   say 'cmin cmax cint 'cmin' 'cmax' 'cint

   i=1
   while (i <= $nmd0)
    'set gxout stat'  ;* first compute means and count good data numbers
*    'd ${var}(x='%i')'
    ii=$ncyc*(i-1)+1
    'd (rms(x='%ii')+rms(x='%ii+2'))'
    ln=sublin(result,11); wd=subwrd(ln,2); a=substr(wd,1,5);sc.i=subwrd(ln,2)
    ln=sublin(result,7); wd=subwrd(ln,8); b=substr(wd,1,3)
    if ( b>0 )
      if( i <=5);
        'set strsiz 0.13 0.13'; yt=yt-yy
        'set line 'cco.i' 'cst.i' 11'; 'draw line 'xt' 'yt' 'xt1' 'yt
*        'set string 'cco.i' bl 6';     'draw string 'xt2' 'yt' 'mdc.i'  ' a'  'b
        'set string 'cco.i' bl 6';     'draw string 'xt2' 'yt' 'mdl.i'  ' a'  'b
        'draw mark 'cma.i' 'xtm' 'yt' 0.10'
      else
        'set strsiz 0.13 0.13'; zyt=zyt-yy
        'set line 'cco.i' 'cst.i' 11'; 'draw line 'zxt' 'zyt' 'zxt1' 'zyt
*        'set string 'cco.i' bl 6';     'draw string 'zxt2' 'zyt' 'mdc.i'  ' a'  'b
        'set string 'cco.i' bl 6';     'draw string 'zxt2' 'zyt' 'mdl.i'  ' a'  'b
        'draw mark 'cma.i' 'zxtm' 'zyt' 0.10'
      endif

      'set gxout line'
      'set display color white'; 'set missconn on';     'set grads off'; 'set grid on'
      'set xlopts 1 6 0.14';     'set ylopts 1 6 0.14'; 'set clopts 1 6 0.0'
      'set vrange 'cmin' 'cmax; 'set ylint 'cint
      'set xlint $xtick'
      'set cstyle 'cst.i; 'set cthick 'cth.i; 'set cmark 'cma.i; 'set ccolor 'cco.i
*      'd ${var}(x='%i')'
    'd (rms(x='%ii')+rms(x='%ii+2'))'
     endif
* Create verification scorecard text files
     if ( $scoretext = 1 ) 
       '${srcgrads}/fprintf.gs 'sc.i' score_${var}_${namedaily1}_'mdc.i'_f'fcstsave'.txt %-7.6f'
     endif
   i=i+1
   endwhile

  'set string 1 bc 7'
  'set strsiz 0.14 0.14'
  'draw string 'titlx' 'titly' ${vnam}: ${title} '
  'set strsiz 0.14 0.14'
  if ( $ncyc >1 )
   'draw string 'titlx2' 'titly2' ${lev} ${reg}, fh'fcstsave
  else
   'draw string 'titlx2' 'titly2' ${lev} ${reg} ${fcycle}Z, fh'fcstsave
  endif
  'set strsiz 0.15 0.15'
  'draw string 'xlabx' 'xlaby' Verification Date'

  'printim ${var}_f'fcstsave'_${namedaily1}.png x800 y800'
  'set vpage off'
*--------
endif
fhour=fhour+${fhout}
endwhile
*-------
'quit'
EOF1
$GRADSBIN/grads -bcp "run ${var}_${outname1}${lev}.gs"


#============================================
fi # $PLOTTYPES (inside levels)
#============================================

#-------------------------------------------------------------------
done  ;# end lev for line plots
#-------------------------------------------------------------------


if [[ $PLOTTYPES != "0" ]] ; then
#--------------------
# remove whitesapce from.png files
# ImageMagic
export PATH=$PATH:/usrx/local/imajik/bin:/usr/bin/convert
export LIBPATH=/lib:/usr/lib
export LIBPATH=$LIBPATH:/usrx/local/imajik/lib

#-- maps
# nn=0
#  for nn in $fhours ; do
#   $IMGCONVERT -crop 0.2x0.2 ${var}p_f${nn}_${namedaily}.png ${var}p_f${nn}_${namedaily}.png
#   if [ $archmon = "YES" ]; then cp ${var}p_f${nn}_${namedaily}.png  ${var}p_f${nn}_${outmon}.png; fi
#  done
#   $IMGCONVERT -crop 0.2x0.2 ${var}pmean_${namedaily}.png ${var}pmean_${namedaily}.png
#   if [ $archmon = "YES" ]; then cp ${var}pmean_${namedaily}.png  ${var}pmean_${outmon}.png; fi

#-- line plots
for lev  in $levlist ; do
  namedaily1=${vnam1}_${lev}_${reg1}
  outmon1=${vnam1}_${lev}_${reg1}_${yyyymm}
  for nn in $fhours ; do
#   $IMGCONVERT -crop 0.2x0.2 ${var}_f${nn}_${namedaily1}.png ${var}_f${nn}_${namedaily1}.png
   $IMGCONVERT -trim ${var}_f${nn}_${namedaily1}.png ${var}_f${nn}_${namedaily1}.png
   if [ $archmon = "YES" ]; then cp ${var}_f${nn}_${namedaily1}.png  ${var}_f${nn}_${outmon1}.png; fi
  done
#  $IMGCONVERT -crop 0.2x0.2 ${var}dieoff_${namedaily1}.png   ${var}dieoff_${namedaily1}.png
#  if [ $archmon = "YES" ]; then cp ${var}dieoff_${namedaily1}.png ${var}dieoff_${outmon1}.png; fi
done  ;# end lev for line plots
#---
#--------------------
fi

#=======================================
done   ;#variable for making plots                    
#=======================================
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#--------------------------------------------------------------------------
fi    ;#end makemap

  ## send graphics to web site 
  #=======================================
  if [ $doftp = "YES" ]; then
    ssh $WEBSERVER "mkdir -p $WEBDIR/$obsv"
    scp -p `ls *png` ${WEBSERVER}:$WEBDIR/$obsv/.
    scp -p `ls *html` ${WEBSERVER}:$WEBDIR/$obsv/.
  fi

#--------------------------------------------------------------------------
done  ;#vnam
done  ;# end reg
done  ;# end obsv
#--------------------------------------------------------------------------
#--------------------------------------------------------------------------


date
exit
