#!/bin/bash

#PBS -j oe
#PBS -A res_stock
#PBS -l walltime=1:00:00
#PBS -l nodes=1
#PBS -q short

module load singularity-container

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
time singularity exec -B /scratch /projects/res_stock/osbeopt.simg ruby measures/$MEASURE_FOLDER/tests/$TEST_FILENAME.rb