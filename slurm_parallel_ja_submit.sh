#!/bin/bash

#
# Usage: $0 <commands-file> -t <walltime-in-hours> -p <partition> -n <nnodes-to-use>
#

if [[ "$#" -eq 0 ]]
then
  echo "Usage: $0 <commands-file> -t <walltime-in-hours> -p <partition> -n <nnodes-to-use>"
  exit 1
fi

inputfile=$1
echo "Input: ${inputfile}"

shift

# Defaults
constraint="avx2"
walltime=48
partition="serial"
nnodes_to_use="8"
while getopts ":c:t:p:n:" opt; do
  case $opt in
    c)
      echo "Entered constraint: $OPTARG" >&2
      constraint="$OPTARG"
      ;;
    t)
      echo "Entered walltime: $OPTARG" >&2
      walltime="$OPTARG"
      ;;
    p)
      echo "Entered partition: $OPTARG" >&2
      partition="$OPTARG"
      ;;
    n)
      echo "Entered number of nodes to use: $OPTARG" >&2
      nnodes_to_use="$OPTARG"
    ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done



DN=$(cd $(dirname ${inputfile});pwd)
FN=$(basename ${inputfile})

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

# Calculate #cores per nodes from constraint
NCORES_PER_NODE=""
case ${constraint} in
avx2)
  NCORES_PER_NODE=28
  ;;
sse)
  NCORES_PER_NODE=12
  ;;
*)
  echo "Error: invalid constraint. Must be 'sse' or 'avx2'"
  exit 1
  ;;
esac

#
# Set number of nodes to use
#
NNODES_HARD_LIMIT=100
nnodes_should_use_max=$(expr $(expr $NJ - 1) / $NCORES_PER_NODE + 1)
if [[ "${nnodes_should_use_max}" -gt ${NNODES_HARD_LIMIT} ]]; then
  nnodes_should_use_max="${NNODES_HARD_LIMIT}"
fi
if [[ "${nnodes_to_use}" -gt "${nnodes_should_use_max}" ]]; then
  nnodes_to_use=${nnodes_should_use_max}
fi

###############################################################
#
# BUILD THE SCRIPT TO RUN
#
###############################################################

cat << EOF > job.$$.sh
#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${NCORES_PER_NODE}
#SBATCH --time=${walltime}:00:00
#SBATCH --output=output-%a.log
#SBATCH --error=error-%a.log
#SBATCH --partition=${partition}
#SBATCH --constraint=${constraint}
#SBATCH --array=1-${nnodes_to_use}

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
start_ja ${NJ} ${nnodes_to_use} ${NCORES_PER_NODE}

# To resubmit this job, run:
#   sbatch job.$$.sh
EOF

#
# Make dynamically generated script executable
#
chmod 755 job.$$.sh

#
# Submit job array
#
sbatch job.$$.sh
