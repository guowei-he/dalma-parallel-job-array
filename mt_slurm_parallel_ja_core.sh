#
# Run through all iterations on this thread
#
serial_thread () {
        local proc_id=$1
	let "proc_id=proc_id-1"
	local array_id
	let "array_id=SLURM_ARRAY_TASK_ID-1"
	local mytask_id
	let "mytask_id=array_id*ntasks_per_node+proc_id"
        local ntasks
	let "ntasks=ntasks_per_node*NN"
	for (( it=0 ; it<${NJ} ; it++ )); do
		let "MY_TASK_ID=it+1"
		export MY_TASK_ID
		local identifier=$(( $it % $ntasks ))
		if [[ "${identifier}" -eq "${mytask_id}" ]]; then
			execute_job
		fi
	done
}

start_ja() {
	NJ=$1
	NN=$2
	ntasks_per_node="$3"
        ncores_per_node="$4"

	if [[ "$NJ" == "" ]]; then
		echo "<# iterations> undefined"
		return
	fi

	if [[ "$NN" == "" ]]; then
		echo "<# nodes> undefined"
		return
	fi

        
	#
	# Verify JA variables
	#
	if [[ -z "$SLURM_ARRAY_TASK_ID" ]]; then
		echo "This is not a job array!"
		exit 1
	fi

	if (( $SLURM_ARRAY_TASK_ID > $NN )); then
		echo "extra ARRAY INDEX $SLURM_ARRAY_TASK_ID skipped (max=$NN)"
		exit 1
	fi

	for (( slot=1 ; slot<=${ntasks_per_node} ; slot++ )); do
		serial_thread ${slot} > /tmp/$$.$slot.o 2> /tmp/$$.$slot.e &
	done

        #
        # Wait for all threads to complete
        #
        wait

        #
        # Reconstruct STDOUT
        #
        for (( slot=1 ; slot<=${ntasks_per_node} ; slot++ )); do
                if [[ -e /tmp/$$.$slot.e ]]; then
                        cat /tmp/$$.$slot.o
                fi
        done

        #
        # Reconstruct STDERR
        #
        for (( slot=1 ; slot<=${ntasks_per_node} ; slot++ )); do
                if [[ -e /tmp/$$.$slot.e ]]; then
                    cat /tmp/$$.$slot.e >&2
                    :
                fi
        done

        #
        # Remove output temp files
        #
        rm /tmp/$$.*.[eo] >& /dev/null

}
