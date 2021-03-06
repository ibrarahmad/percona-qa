#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# User variables
MAIN_SQL=./main-ms-ps-md.sql
WORKDIR=/tmp/generate
OUTPUT=/tmp/out.sql
THREADS=100
APPEND_TO_OUTPUT=1

# Output function
echoit(){ echo "[$(date +'%T')] $1"; }

# RANDOM: Random entropy pool init
RANDOM=$(date +%s%N | cut -b14-19)

# Work directory setup & check main SQL input is available
rm -Rf ${WORKDIR}; mkdir ${WORKDIR}
if [ ! -d ${WORKDIR} ]; then echo "Assert: ${WORKDIR} does not exist after creation"; exit 1; fi
if [ ! -r ${MAIN_SQL} ]; then echo "Assert: current directory does not contain ${MAIN_SQL}"; exit 1; fi

# Stage 1: Subdivide main input sql file
echoit "Stage 1: Subdividing main input sql file..."
grep "^SELECT " ${MAIN_SQL} > ${WORKDIR}/1.sql1
grep "^INSERT " ${MAIN_SQL} > ${WORKDIR}/2.sql1
grep "^UPDATE " ${MAIN_SQL} > ${WORKDIR}/3.sql1
grep "^DROP " ${MAIN_SQL} > ${WORKDIR}/4.sql1
grep "^CREATE " ${MAIN_SQL} > ${WORKDIR}/5.sql1
grep "^RENAME " ${MAIN_SQL} > ${WORKDIR}/6.sql1
grep "^TRUNCATE " ${MAIN_SQL} > ${WORKDIR}/7.sql1
grep "^REPLACE " ${MAIN_SQL} > ${WORKDIR}/8.sql1
grep "^START " ${MAIN_SQL} > ${WORKDIR}/9.sql1
grep "^SAVEPOINT " ${MAIN_SQL} > ${WORKDIR}/10.sql1
grep "^ROLLBACK " ${MAIN_SQL} > ${WORKDIR}/11.sql1
grep "^RELEASE " ${MAIN_SQL} > ${WORKDIR}/12.sql1
grep "^LOCK " ${MAIN_SQL} > ${WORKDIR}/13.sql1
grep "^XA " ${MAIN_SQL} > ${WORKDIR}/14.sql1
grep "^PURGE " ${MAIN_SQL} > ${WORKDIR}/15.sql1
grep "^RESET " ${MAIN_SQL} > ${WORKDIR}/16.sql1
grep "^SHOW " ${MAIN_SQL} > ${WORKDIR}/17.sql1
grep "^CHANGE " ${MAIN_SQL} > ${WORKDIR}/18.sql1
grep "^START " ${MAIN_SQL} > ${WORKDIR}/19.sql1
grep "^STOP " ${MAIN_SQL} > ${WORKDIR}/20.sql1
grep "^PREPARE " ${MAIN_SQL} > ${WORKDIR}/21.sql1
grep "^EXECUTE " ${MAIN_SQL} > ${WORKDIR}/22.sql1
grep "^DEALLOCATE " ${MAIN_SQL} > ${WORKDIR}/23.sql1
grep "^BEGIN " ${MAIN_SQL} > ${WORKDIR}/24.sql1
grep "^DECLARE " ${MAIN_SQL} > ${WORKDIR}/25.sql1
grep "^FETCH " ${MAIN_SQL} > ${WORKDIR}/26.sql1
grep "^CASE " ${MAIN_SQL} > ${WORKDIR}/27.sql1
grep "^IF " ${MAIN_SQL} > ${WORKDIR}/28.sql1
grep "^ITERATE " ${MAIN_SQL} > ${WORKDIR}/29.sql1
grep "^LEAVE " ${MAIN_SQL} > ${WORKDIR}/30.sql1
grep "^LOOP " ${MAIN_SQL} > ${WORKDIR}/31.sql1
grep "^REPEAT " ${MAIN_SQL} > ${WORKDIR}/32.sql1
grep "^RETURN " ${MAIN_SQL} > ${WORKDIR}/33.sql1
grep "^WHILE " ${MAIN_SQL} > ${WORKDIR}/34.sql1
grep "^CLOSE " ${MAIN_SQL} > ${WORKDIR}/35.sql1
grep "^GET " ${MAIN_SQL} > ${WORKDIR}/36.sql1
grep "^RESIGNAL " ${MAIN_SQL} > ${WORKDIR}/37.sql1
grep "^SIGNAL " ${MAIN_SQL} > ${WORKDIR}/38.sql1
grep "^EXPLAIN " ${MAIN_SQL} > ${WORKDIR}/39.sql1
grep "^DESCRIBE " ${MAIN_SQL} > ${WORKDIR}/40.sql1
grep "^HELP " ${MAIN_SQL} > ${WORKDIR}/41.sql1
grep "^USE " ${MAIN_SQL} > ${WORKDIR}/42.sql1
grep "^GRANT " ${MAIN_SQL} > ${WORKDIR}/43.sql1
grep "^ANALYZE " ${MAIN_SQL} > ${WORKDIR}/44.sql1
grep "^CHECK " ${MAIN_SQL} > ${WORKDIR}/45.sql1
grep "^CHECKSUM " ${MAIN_SQL} > ${WORKDIR}/46.sql1
grep "^OPTIMIZE " ${MAIN_SQL} > ${WORKDIR}/47.sql1
grep "^REPAIR " ${MAIN_SQL} > ${WORKDIR}/48.sql1
grep "^INSTALL " ${MAIN_SQL} > ${WORKDIR}/49.sql1
grep "^UNINSTALL " ${MAIN_SQL} > ${WORKDIR}/50.sql1
grep "^BINLOG " ${MAIN_SQL} > ${WORKDIR}/51.sql1
grep "^CACHE " ${MAIN_SQL} > ${WORKDIR}/52.sql1
grep "^FLUSH " ${MAIN_SQL} > ${WORKDIR}/53.sql1
grep "^KILL " ${MAIN_SQL} > ${WORKDIR}/54.sql1
grep "^LOAD " ${MAIN_SQL} > ${WORKDIR}/55.sql1
grep "^CALL " ${MAIN_SQL} > ${WORKDIR}/56.sql1
grep "^DELETE " ${MAIN_SQL} > ${WORKDIR}/57.sql1
grep "^DO " ${MAIN_SQL} > ${WORKDIR}/58.sql1
grep "^HANDLER " ${MAIN_SQL} > ${WORKDIR}/59.sql1
grep "^LOAD DATA " ${MAIN_SQL} > ${WORKDIR}/60.sql1
grep "^LOAD XML " ${MAIN_SQL} > ${WORKDIR}/61.sql1
grep "^ALTER " ${MAIN_SQL} > ${WORKDIR}/62.sql1
grep "^SET" ${MAIN_SQL} > ${WORKDIR}/63.sql1

# Stage 2: Make secondary random files
echoit "Stage 2: Making secondary random files based on the files generated by stage 1..."
cd ${WORKDIR}
for FILE in $(ls ?.sql1 ??.sql1); do
  if [ $(wc -c ${FILE}) -eq 0 ]; then rm ${FILE}; continue; fi
  shuf --random-source=/dev/urandom ${FILE} > ${FILE}2
done

generate(){
  PID_OF_SUBSHELL=$BASHPID  # Hack makes variables subshell-dependent, with thanks, http://askubuntu.com/questions/305858/how-to-know-process-pid-of-bash-function-running-as-child
  while true; do
    #COUNTER=$[ ${COUNTER} + 1 ]
    FILE1[${PID_OF_SUBSHELL}]=$(ls ?.sql1 ??.sql1 | sort -R | head -n1)
    #FILE2[${PID_OF_SUBSHELL}]=$(ls ?.sql2 ??.sql2 | sort -R | head -n1)  # Creates many non-sensical queries
    FILE2[${PID_OF_SUBSHELL}]=$(echo ${FILE1[${PID_OF_SUBSHELL}]} | sed 's|sql1|sql2|')
    LENGHT1[${PID_OF_SUBSHELL}]=$(wc -l ${FILE1[${PID_OF_SUBSHELL}]} | awk '{print $1}')
    LENGHT2[${PID_OF_SUBSHELL}]=$(wc -l ${FILE2[${PID_OF_SUBSHELL}]} | awk '{print $1}')
    LINE1[${PID_OF_SUBSHELL}]=$(cat ${FILE1[${PID_OF_SUBSHELL}]} | head -n$[$RANDOM % ${LENGHT1[${PID_OF_SUBSHELL}]} + 1] | tail -n1 | sed 's|;||;s|[ \t][ \t]\+| |')
    LINE2[${PID_OF_SUBSHELL}]=$(cat ${FILE2[${PID_OF_SUBSHELL}]} | head -n$[$RANDOM % ${LENGHT2[${PID_OF_SUBSHELL}]} + 1] | tail -n1 | sed 's|;||;s|[ \t][ \t]\+| |')
    #echo "LINE1: ${LINE1[${PID_OF_SUBSHELL}]}"; echo "LINE2: ${LINE2[${PID_OF_SUBSHELL}]}"  # Debug
    COUNT1[${PID_OF_SUBSHELL}]=$(echo "${LINE1[${PID_OF_SUBSHELL}]}" | tr ' ' '\n' | wc -l)
    COUNT2[${PID_OF_SUBSHELL}]=$(echo "${LINE2[${PID_OF_SUBSHELL}]}" | tr ' ' '\n' | wc -l)
    if [ ${COUNT2[${PID_OF_SUBSHELL}]} -lt ${COUNT1[${PID_OF_SUBSHELL}]} ]; then 
      COUNT1[${PID_OF_SUBSHELL}]=${COUNT2[${PID_OF_SUBSHELL}]};  # Ensure that the capture lenght is less then either query's lenght
    fi
    CLAUSES1[${PID_OF_SUBSHELL}]=$[$RANDOM % $[${COUNT1[${PID_OF_SUBSHELL}]} -1] +1]  # COUNT-1: Ensure that we do not capture the full query (i.e. -1 clause)
    CLAUSES2[${PID_OF_SUBSHELL}]=$[${COUNT2[${PID_OF_SUBSHELL}]} - ${CLAUSES1[${PID_OF_SUBSHELL}]}]
    SUBS1[${PID_OF_SUBSHELL}]="$(echo "${LINE1[${PID_OF_SUBSHELL}]}" | tr ' ' '\n' | head -n${CLAUSES1[${PID_OF_SUBSHELL}]})"
    SUBS2[${PID_OF_SUBSHELL}]="$(echo "${LINE2[${PID_OF_SUBSHELL}]}" | tr ' ' '\n' | tail -n${CLAUSES2[${PID_OF_SUBSHELL}]})"
    echo "$(echo "${SUBS1[${PID_OF_SUBSHELL}]} ${SUBS2[${PID_OF_SUBSHELL}]};" | tr '\n' ' ' | sed 's|[ \t][ \t]\+| |')" >> ${OUTPUT}
  done
}

# Stage 3: Generate random SQL
echoit "Stage 3: Generating ramdom SQL based on the files generated by stages 1 and 2..."
#COUNTER=0
if [ ${APPEND_TO_OUTPUT} -eq 0 ]; then rm -f ${OUTPUT}; fi
PIDS=
for THREAD in $(seq 1 $THREADS); do
  generate &
  PID=$!
  echoit "Thread with pid ${PID} started!"
  PIDS="${PID} ${PIDS}"
done
echoit "To terminate processes, use: kill -9 ${PIDS}"
