#!/bin/bash

#
# Usage: launcher <file-with-list-of-things-to-do>
#
if (( $# == 0 )); then
	echo "Usage: $0 <file-with-list-of-commands>"
	exit 1
fi

DN=$(cd $(dirname $1);pwd)
FN=$(basename $1)

if [[ ! -e $DN/$FN ]]; then
	echo "command file does not exist"
	exit 1
fi

#
# Find how many jobs are to run
#
NJ=$(cat $DN/$FN | wc -l)
if (( $NJ <= 0 )); then
	echo "invalid command file"
	exit 1
fi

#
# Set number of job clusters (number of actual iterations as seen by SLURM)
#
NCORES=28
NN=$(expr $(expr $NJ - 1) / $NCORES + 1)

#
# Limit number of nodes that can be used at once
#
if (( $NN > 8 )); then
	NN=8
fi

#
# Set number of jobs per node
#
STP=$(expr $(expr $NJ + $NN - 1) / $NN)

###############################################################
#
# BUILD THE SCRIPT TO RUN
#
###############################################################

cat << EOF > job.$$.sh
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=28
#SBATCH --ntasks-per-node=28
#SBATCH --time=00:20:00
#SBATCH --output=output.log

execute_job() {
    #
    # retrieve line and execute
    # 
    LIN=\$(awk "NR == \$MY_TASK_ID {print;exit}" $DN/$FN)
    echo \$LIN > /tmp/\$\$-\$SLURM_JOBID-\$MY_TASK_ID-cmd.tmp
    source /tmp/\$\$-\$SLURM_JOBID-\$MY_TASK_ID-cmd.tmp
    rm -f /tmp/\$\$-\$SLURM_JOBID-\$MY_TASK_ID-cmd.tmp >& /dev/null
}


source ./slurm_parallel_ja_core.sh
start_ja $NJ $NN

# To resubmit this job, run:
#   sbatch --array=1-$NN job.$$.sh
EOF

#
# Make dynamically generated script executable
#
chmod 755 job.$$.sh

#
# Submit job array ('-n' to have exclusive use of node)
#
sbatch --array=1-$NN job.$$.sh
