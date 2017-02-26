#!/bin/bash
#
# It generates a job script of parallel job array,
#   which will paralllely execute all commands in the file.
#
# Usage:
#   slurm-parallel-ja-submit-multi-threads.sh <inputfile> -c <Number of threads per process, default 1> -t <max_time (in hours, default 8)> 
#


main() {
  # Validate and parse input
  if [[ "$#" -eq 0 ]]
  then
    echo "Usage: slurm-parallel-ja_submit-multi-threads.sh <inputfile> -c <Number of threads per process, default 1> -t <max_time (in h, default 8)>"
    exit 1
  fi
  local inputfile="$1"
  if [[ ! -f "${inputfile}" ]]
  then
    echo "${inputfile} does not exist"
    exit 1
  fi
  shift
  echo "Input: ${inputfile}"
  local nthreads=1
  local max_time=1
  while getopts ":c:t:" opt; do
    case $opt in
      c)
        echo "Entered #threads per proc: $OPTARG" >&2
	nthreads="$OPTARG"
        ;;
      t)
        echo "Entered #time: $OPTARG hour(s)" >&2
	max_time="$OPTARG"
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

  DN=$(cd $(dirname $inputfile);pwd)
  FN=$(basename $inputfile)

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
  let "ntasks_per_node=NCORES/nthreads"
  let "effective_procs_per_node=ntasks_per_node*nthreads"
  if [[ "${effective_procs_per_node}" -ne "${NCORES}" ]]; then
    echo "Wrong threads per process"
    exit 1
  fi
  let "NN=(NJ+ntasks_per_node-1)/ntasks_per_node"

  #
  # Limit number of nodes that can be used at once
  #
  if (( $NN > 8 )); then
  	NN=8
  fi

###############################################################
#
# BUILD THE SCRIPT TO RUN
#
###############################################################

cat << EOF > job.$$.sh
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=${ntasks_per_node}
#SBATCH --cpus-per-task=${nthreads}
#SBATCH --time=${max_time}:00:00
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

source ./mt_slurm_parallel_ja_core.sh
start_ja $NJ $NN ${ntasks_per_node} ${NCORES}

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
echo "Run this command. Change walltime in job script if necessary"
echo "sbatch --array=1-$NN job.$$.sh"

}

main "$@"
