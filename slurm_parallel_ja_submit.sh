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
nnodes_to_use=""
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
      echo "Entered number of jobs in array: $OPTARG" >&2
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
NCORES=""
case ${constraint} in
avx2)
  NCORES=28
  ;;
sse)
  NCORES=12
  ;;
*)
  echo "Error: invalid constraint. Must be 'sse' or 'avx2'"
  exit 1
  ;;
esac

#
# Set number of job clusters (number of actual iterations as seen by SLURM)
#
if [[ -z "${NCORES}" ]]; then
  echo "Error: NCORES is not set"
  exit 1
fi
NN=$(expr $(expr $NJ - 1) / $NCORES + 1)

# From command line
if [[ ! -z "${nnodes_to_use}" ]]; then
  NN=${nnodes_to_use}
fi

#
# Limit number of nodes that can be used at once
#
MAXNN=8
if (( $NN > "${MAXNN}" )); then
	NN="${MAXNN}"
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
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${NCORES}
#SBATCH --time=${walltime}:00:00
#SBATCH --output=output-%a.log
#SBATCH --partition=${partition}
#SBATCH --constraint=${constraint}
#SBATCH --array=1-${NN}

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
start_ja $NJ $NN $NCORES

# To resubmit this job, run:
#   sbatch job.$$.sh
EOF

#
# Make dynamically generated script executable
#
chmod 755 job.$$.sh

#
# Submit job array ('-n' to have exclusive use of node)
#
sbatch job.$$.sh
