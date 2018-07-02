#!/bin/bash

#PBS -j oe
#PBS -A res_stock
#PBS -l walltime=2:00:00
#PBS -l nodes=1
#PBS -q short
#PBS -l feature=24core

module load singularity-container

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
cd ..
time singularity exec -B /scratch /projects/res_stock/osbeopt.simg ruby measures/$MEASURE_FOLDER/tests/$TEST_FILENAME.rb