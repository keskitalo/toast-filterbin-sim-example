#!/bin/bash

ulimit -c unlimited

ntask=4
groupsize=$ntask

export OMP_NUM_THREADS=4

date

# Make a fake focalplane

freq=150
focalplane=focalplane_${freq}GHz.h5
if [[ ! -e $focalplane ]]; then
    echo "Generating $focalplane"
    toast_fake_focalplane \
	--min_pix 100 \
	--fov_deg 10 \
	--psd_net 1e-3 \
	--psd_alpha 1.0 \
	--psd_fknee 0.05 \
	--bandcenter_ghz ${freq} \
	--sample_rate 10 \
	--out $focalplane \
	>& ${focalplane/.h5/.log}
fi

# Make an observing schedule

lon_max=65.0
lon_min=15.0
lat_max=-30.0
lat_min=-50
schedule="schedule.txt"
if [[ ! -e $schedule ]]; then
    echo "Generating $schedule"
    toast_ground_schedule \
	--site-lat " -22.958064" \
	--site-lon " -67.786222" \
	--site-alt "5200" \
	--start "2025-07-01 00:00:00" \
	--stop "2025-07-02 00:00:00" \
	--lock-az-range \
	--ces-max-time-s 1800 \
	--sun-avoidance-angle 0 \
	--moon-avoidance-angle 0 \
	--elevations-deg 55 \
	--patch south,1,${lon_max},${lat_max},${lon_min},${lat_min} \
	--out ${schedule} \
	>& ${schedule/.txt/.log}

    # Split the schedule into many short files
    echo "Splitting the schedule"

    let nline=`wc -l $schedule | awk '{print $1}'`-3
    echo "Found $nline entries in $schedule"

    head -n 3 $schedule > header
    tail -n $nline $schedule > body

    outdir=split_schedule
    mkdir -p $outdir

    split \
	--numeric-suffixes \
	--lines=1 \
	--suffix-length=3 \
	--additional-suffix=".txt" \
	body \
	${outdir}/schedule

    for fname in ${outdir}/*txt; do
	mv ${fname} temp
	cat header temp > ${fname}
    done

    rm -f header body temp
fi

# Write a default parameter file that can be used as a reference

defaults=defaults.toml
if [[ ! -e $defaults ]]; then
    toast_sim_ground.py --focalplane X --schedule X --defaults_toml $defaults >& /dev/null
    echo "Default parameters written to $defaults"
fi

# If no parameter file exists yet, make a copy of the defaults

params=params.toml
if [[ ! -e $params ]]; then
    cp defaults.toml $params
    echo "Copied $defaults to $params"
fi

# Simulate

for schedule in split_schedule/*txt; do
    rootname=$(basename $schedule .txt)

    logdir=split_logs
    mkdir -p $logdir

    outdir=out/${rootname}
    mkdir -p $outdir

    logfile=${logdir}/${rootname}.log
    if [[ -e $logfile ]]; then
	echo "$(date) : $logfile exists"
    else
	date
	echo "$(date) : Writing $logfile"
	nice -n 19 mpiexec -n $ntask \
	     toast_sim_ground.py \
	     --config $params \
	     --focalplane $focalplane \
	     --schedule $schedule \
	     --out $outdir \
	     >& ${logfile}
	echo "$(date) : Done"
	exit
    fi

done

echo "$(date) : All done"
