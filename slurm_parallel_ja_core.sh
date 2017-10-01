#
# Run through all iterations on this thread
#
serial_thread () {
	for (( it=$1 ; it<=$2 ; it++ )); do
		export MY_TASK_ID=$it
		execute_job
	done
}

start_ja() {
	NJ=$1
	NN=$2
	NT=$3

	if [[ "$NJ" == "" ]]; then
		echo "<# iterations> undefined"
		echo "usage: start_ja <# jobs> <# nodes> <# cores per node>"
		return
	fi

	if [[ "$NN" == "" ]]; then
		echo "<# SLURM jobs> undefined"
		echo "usage: start_ja <# jobs> <# nodes> <# cores per node>"
		return
	fi
	
	if [[ "$NT" == "" ]]; then
		echo "<# cores each node> undefined"
		echo "usage: start_ja <# jobs> <# nodes> <# cores per node>"
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

	#
	# How many processor slots to use is now from $NT
	#
	ITER=$(expr $(expr $NJ + $NN - 1) / $NN)
	#
	# Split work across all slots
	#
        WRK=$(expr $(expr $ITER + $NT - 1) / $NT)
	FIRST=$(expr $(expr $SLURM_ARRAY_TASK_ID - 1) \* $ITER + 1)
	LAST=$NJ
	FFIRST=$FIRST
	ILAST=$(expr $FFIRST + $ITER - 1)
	
	for (( slot=1 ; slot<=$NT ; slot++ )); do
		if (( $LAST >= $FFIRST)); then
			LLAST=$(expr $FFIRST + $WRK - 1)
                        if (( $LLAST > $ILAST )); then
				LLAST=$ILAST
			fi
			if (( $LLAST > $LAST )); then
				LLAST=$LAST
			fi
			# 
			# Note STDOUT / STDERR redirection into temp files
			#
			serial_thread $FFIRST $LLAST > /tmp/$$.$slot.o 2> /tmp/$$.$slot.e &
		fi
		FFIRST=$(expr $FFIRST + $WRK)
	done

	#
	# Wait for all threads to complete
	#
	wait

	#
	# Reconstruct STDOUT
	#
	for (( slot=1 ; slot<=$NT ; slot++ )); do
		if [[ -e /tmp/$$.$slot.o ]]; then
			cat /tmp/$$.$slot.o
		fi
	done

	#
	# Reconstruct STDERR
	#
	for (( slot=1 ; slot<=$NT ; slot++ )); do
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
