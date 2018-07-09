#!/bin/bash

#PBS -j oe
#PBS -A res_stock
#PBS -l walltime=4:00:00
#PBS -l nodes=1
#PBS -q short

module load singularity-container

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
time SINGULARITYENV_NUM_NODES=$NUM_NODES singularity exec -B /scratch /projects/res_stock/osbeopt.simg ruby measures/$MEASURE_FOLDER/tests/$TEST_FILENAME.rb

time ruby measures/$MEASURE_FOLDER/tests/combine_results.rb