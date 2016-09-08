#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# The name of this script (pquery-prep-red.sh) was kept short so as to not clog directory listings - it's full name would be ./pquery-prepare-reducer.sh

# To aid with correct bug to testcase generation for pquery trials, this script creates a local run script for reducer and sets #VARMOD#.
# This handles crashes/asserts/Valgrind issues for the moment only. Could be expanded later for other cases, and to handle more unforseen situations.
# Query correctness: data (output) correctness (QC DC) trial handling was also added 11 May 2016

# Improvement ideas
# - It would be better if failing queries were added like this; 3x{query_from_err_log,query_from_core},3{SELECT 1} instead of 3{query_from_core},3{query_from_err_log},3{SELECT 1}

# User configurable variables
VALGRIND_OVERRIDE=0    # If set to 1, Valgrind issues are handled as if they were a crash (core dump required)

# Internal variables
SCRIPT_PWD=$(cd `dirname $0` && pwd)
WORKD_PWD=$PWD
REDUCER="${SCRIPT_PWD}/reducer.sh"
DOCKER_COMPOSE_YML="`grep '^[ \t]*DOCKER_COMPOSE_YML[ \t]*=[ \t]*' ${SCRIPT_PWD}/pquery-run.sh | sed 's|^[ \t]*DOCKER_COMPOSE_YML[ \t]*=[ \t]*[ \t]*||' | sed 's|${SCRIPT_PWD}||'`"
DOCKER_COMPOSE_LOC="`grep '^[ \t]*DOCKER_COMPOSE_LOC[ \t]*=[ \t]*' ${SCRIPT_PWD}/pquery-run.sh | sed 's|^[ \t]*DOCKER_COMPOSE_LOC[ \t]*=[ \t]*[ \t]*||' | sed 's|${SCRIPT_PWD}||'`"

# Check if this is a pxc run
if [ "$(grep 'PXC Mode:' ./pquery-run.log 2> /dev/null | sed 's|^.*PXC Mode[: \t]*||' )" == "TRUE" ]; then
  PXC=1
else
  PXC=0
fi

# Check if this an automated (pquery-reach.sh) run
if [ "$1" == "reach" ]; then
  REACH=1  # Minimal output, and no 2x enter required
else
  REACH=0  # Normal output
fi

# Check if this is a query correctness run
if [ $(ls */*.out */*.sql 2>/dev/null | egrep -oi "innodb|rocksdb|tokudb|myisam|memory|csv|ndb|merge" | wc -l) -gt 0 ]; then
  if [ "$1" == "noqc" ]; then  # Even though query correctness trials were found, process this run as a crash/assert run only
    QC=0
  else
    QC=1
  fi
else
  QC=0
fi

# Variable checks
if [ ! -r ${REDUCER} ]; then
  echo "Assert: this script could not read reducer.sh at ${REDUCER} - please set REDUCER variable inside the script correctly."
  exit 1
fi

# Current location checks
if [ `ls */*thread-[1-9]*.sql 2>/dev/null | wc -l` -gt 0 ]; then
  echo -e "** NOTE ** Multi-threaded trials (./*/*thread-[1-9]*.sql) were found. For multi-threaded trials, now the 'total sql' file containing all executed queries (as randomly generated by pquery-run.sh prior to pquery's execution) is used. Reducer scripts will be generated as per normal (with the relevant multi-threaded options already set), and they will be pointed to these (i.e. one file per trial) SQL testcases. Failing sql from the coredump and the error log will be auto-added (interleaved multile times) to ensure better reproducibility. A new feature has also been added to reducer.sh, allowing it to reduce multi-threaded testcases multi-threadely using pquery --threads=x, each time with a reduced original (and still random) sql file. If the bug reproduces, the testcase is reduced further and so on. This will thus still end up with a very small testcase, which can be then used in combination with pquery --threads=x.\n"
  MULTI=1
fi
if [ ${QC} -eq 0 ]; then
  if [ `ls */*thread-0.sql 2>/dev/null | wc -l` -eq 0 ]; then
    echo "Assert: there were 0 pquery sql files found (./*/*thread-0.sql) in subdirectories of the current directory. Terminating."
    exit 1
  fi
else
  echo "Query correctness trials found! Only processing query correctness results. To process crashes/asserts pass 'noqc' as the first option to this script (pquery-prep-red.sh noqc)"
fi

WSREP_OPTION_CHECK=0
if [ `ls */WSREP_PROVIDER_OPT* 2>/dev/null | wc -l` -gt 0 ];then
  WSREP_OPTION_CHECK=1
  WSREP_PROVIDER_OPTIONS=
fi

NEW_MYEXTRA_METHOD=0
if [ `ls ./*/MYEXTRA* 2>/dev/null | wc -l` -gt 0 ]; then  # New MYEXTRA/MYSAFE variables pass & VALGRIND run check method as of 2015-07-28 (MYSAFE & MYEXTRA stored in a text file inside the trial dir, VALGRIND file created if used). All settings will be set automatically for each trial (and can be checked in the output of this script)
  NEW_MYEXTRA_METHOD=1  
  MYEXTRA=
  VALGRIND_CHECK=0
elif [ `ls ./pquery-run.log 2>/dev/null | wc -l` -eq 0 ]; then  # Older (backward compatible) methods for retrieving MYEXTRA/MYSAFE
  echo -e "Assert: this script did not find a file ./pquery-run.log (the main pquery-run log file) in this directory. Was this run generated by pquery-run.sh?\n"
  echo -e "WARNING: Though this script does not necessarily need the ./pquery-run.log file to obtain the MYEXTRA and MYSAFE settings (MYEXTRA are extra settings passed to mysqld, MYSAFE is similar but it is specifically there to ensure QA tests are of a reasonable quality), PLEASE NOTE that if any MYEXTRA/MYSAFE=\"....\" settings were used when using pquery-run.sh, then these settings will now not end up in the reducer<nr>.sh scripts that this script produces. The result is likely that some issues will not reproduce as mysqld was not started with the same settings... If you have the original pquery-run.sh script as you used it to generate this workdir, you could extract the MYEXTRA and MYSAFE strings from there, compile them into one and add them to the reducer<nr>.sh scripts that do not reproduce, which is an easy/straightforward solution. Yet, if you want to re-generate all reducer<nr>.sh scripts with the right settings in place, just copy the MYEXTRA and MYSAFE lines and add them to a file called ./pquery-run.log as follows:\n"
  echo "MYEXTRA: --some_option --some_option_2 etc. (Important: ensure all is on one line with no line breaks!)"
  echo "MYSAFE: --some_option --some_option_2 etc. (Important: ensure all is on one line with no line breaks!)"
  echo "Then, re-run this script. It will extract the MYEXTRA/MYSAFE settings from the ./pquery-run.log and use these in the resulting reducer<nr>.sh scripts. Make sure to have the syntax exactly matches the above, with quotes (\") removed etc."
  if [ -r ${SCRIPT_PWD}/pquery-run.sh ]; then
    MYEXTRA="`grep '^[ \t]*MYEXTRA[ \t]*=[ \t]*"' ${SCRIPT_PWD}/pquery-run.sh | sed 's|^[ \t]*MYEXTRA[ \t]*=[ \t]*"[ \t]*||;s|#.*$||;s|"[ \t]*$||'`"
    MYSAFE="`grep '^[ \t]*MYSAFE[ \t]*=[ \t]*"'  ${SCRIPT_PWD}/pquery-run.sh | sed 's|^[ \t]*MYSAFE[ \t]*=[ \t]*"[ \t]*||;s|#.*$||;s|"[ \t]*$||'`"
    echo -e "Now, to make it handy for you, this script has already pre-parsed the pquery-run.sh found here: ${SCRIPT_PWD}/pquery-run.sh (is this the one you used?) and compiled the following MYEXTRA and MYSAFE settings from it:\n"
    echo "MYEXTRA: $MYEXTRA"
    echo "MYSAFE: $MYSAFE"
    echo -e "\nIf this is the script (and thus MYEXTRA/MYSAFE) settings you used, hit enter 3x now and we will use these settings. However, if you are not sure if ${SCRIPT_PWD}/pquery-run.sh was the script you used, or the MYEXTRA/MYSAFE settings shown above do not look correct then press CTRL-C to abort now. Please note one other gotcha here: if you did a bzr pull since your ${SCRIPT_PWD}/pquery-run.sh run, it is possible and even regularly 'likely' that your MEXTRA settings were changed to whatever is in the percona-qa tree (and they have been changing...). Thus, be sure before you hit enter twice. Also, it would make sense to make a copy of pquery-run.sh (pquery-run-<date>.sh for example) and save it in the workdir as a backup. If you use a version of pquery-run.sh later then 16-10-2014, then pquery-run.sh already auto-saves a copy of itself in the workdir. Note: this script (pquery-prep-red.sh) may be extended further later to check for the saved copy of pquery-run.sh."
      echo "Btw, note that only MYEXTRA is used by reducer, so MYSAFE string is compiled into MYEXTRA."
    read -p "Press ENTER or CTRL-C now... 1..."
    read -p "Press ENTER or CTRL-C now... 2..."
    read -p "Press ENTER or CTRL-C now... 3..."
    echo "Ok, using MYEXTRA/MYSAFE as listed above"
    MYEXTRA="$MYEXTRA $MYSAFE"
  else
    echo "If you would like this script to continue *WITHOUT* any MYEXTRA and MYSAFE settings (i.e. some issues will likely fail to reproduce), hit enter 3x now. If you would like to take one of the two approaches listed above (though note we could not locate a pquery-run.sh in ${SCRIPT_PWD} which is another oddity), press CTRL-C and action as described."
    echo "Btw, note that only MYEXTRA is used by reducer, so MYSAFE string is compiled into MYEXTRA, which in this case simply results in an empty string."
    read -p "Press ENTER or CTRL-C now... 1..."
    read -p "Press ENTER or CTRL-C now... 2..."
    read -p "Press ENTER or CTRL-C now... 3..."
    echo "Ok, using empty MYEXTRA/MYSAFE (Note that only MYEXTRA is used by reducer, so MYSAFE string is compiled into MYEXTRA)"
    MYEXTRA=""
    MYSAFE=""  # This and the next line are not needed, just leaving them here for if logic comprehension / if they ever need something added etc.
    MYEXTRA="$MYEXTRA $MYSAFE"
  fi
else
  MYEXTRA="`grep 'MYEXTRA:' ./pquery-run.log | sed 's|^.*MYEXTRA[: \t]*||'`"
  MYSAFE="`grep 'MYSAFE:' ./pquery-run.log | sed 's|^.*MYSAFE[: \t]*||'`"
  if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
    echo "Using the following MYEXTRA/MYSAFE settings (found in the ./pquery-run.log stored in this directory):"
    echo "======================================================================================================================================================"
    echo "MYEXTRA: $MYEXTRA"
    echo "MYSAFE: $MYSAFE"
    echo "======================================================================================================================================================"
    echo "If you agree that these look correct, hit enter twice. If something looks wrong, press CTRL+C to abort."
    echo "(To learn more, you may want to read some of the info/code in this script (pquery-prep-red.sh) in the 'Current location checks' var checking section.)"
    echo "Btw, note that only MYEXTRA is used by reducer, so MYSAFE string will be merged into MYEXTRA for the resulting reducer<nr>.sh scripts."
    echo "======================================================================================================================================================"
    read -p "Press ENTER or CTRL-C now... 1..."
    read -p "Press ENTER or CTRL-C now... 2..."
    echo "Ok, using MYEXTRA/MYSAFE as listed above"
  fi
  MYEXTRA="$MYEXTRA $MYSAFE"
fi

#Check MS/PS pquery binary
#PQUERY_BIN="`grep 'pquery Binary' ./pquery-run.log | sed 's|^.*pquery Binary[: \t]*||' | head -n1`"    # < swap back to this one once old runs are gone (upd: maybe not. Issues.)
PQUERY_BIN=$(echo "$(grep -ihm1 "^[ \t]*PQUERY_BIN=" *pquery*.sh | sed 's|[ \t]*#.*$||;s|PQUERY_BIN=||')" | sed "s|\${SCRIPT_PWD}|${SCRIPT_PWD}|" | head -n1)
echo "pquery binary used: ${PQUERY_BIN}"

if [ "${PQUERY_BIN}" == "" ]; then
  echo "Assert! pquery binary used could not be auto-determined. Check script around \$PQUERY_BIN initialization."
  exit 1
fi

extract_queries_core(){
  echo "* Obtaining quer(y)(ies) from the trial's coredump (core: ${CORE})"
  . ${SCRIPT_PWD}/pquery-failing-sql.sh ${TRIAL} 1
  if [ "${MULTI}" == "1" ]; then
    CORE_FAILURE_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
    echo "  > $[ $CORE_FAILURE_COUNT ] quer(y)(ies) added with interleave sql function to the SQL trace"
  else
    for i in {1..3}; do
      BEFORESIZE=`cat ${INPUTFILE} | wc -l`
      cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing >> ${INPUTFILE}
      AFTERSIZE=`cat ${INPUTFILE} | wc -l`
    done
    echo "  > $[ $AFTERSIZE - $BEFORESIZE ] quer(y)(ies) added 3x to the SQL trace"
    rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
  fi
}
  
extract_queries_error_log(){
  # Extract the "Query:" crashed query from the error log (making sure we have the 'Query:' one at the end)
  echo "* Obtaining quer(y)(ies) from the trial's mysqld error log (if any)"
  . ${SCRIPT_PWD}/pquery-failing-sql.sh ${TRIAL} 2
  if [ "${MULTI}" == "1" ]; then
    FAILING_SQL_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
    echo "  > $[ $FAILING_SQL_COUNT - ${CORE_FAILURE_COUNT} ] quer(y)(ies) will be added with interleave sql function to the SQL trace"
  else
    for i in {1..3}; do
      BEFORESIZE=`cat ${INPUTFILE} | wc -l`
      cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing >> ${INPUTFILE}
      AFTERSIZE=`cat ${INPUTFILE} | wc -l`
    done
    echo "  > $[ $AFTERSIZE - $BEFORESIZE ] quer(y)(ies) added 3x to the SQL trace"
    rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
  fi
}

add_select_ones_to_trace(){  # Improve issue reproducibility by adding 3x SELECT 1; to the sql trace
  echo "* Adding additional 'SELECT 1;' queries to improve issue reproducibility"
  if [ ! -f ${INPUTFILE} ]; then touch ${INPUTFILE}; fi
  for i in {1..3}; do
    echo "SELECT 1;" >> ${INPUTFILE}
  done
  echo "  > 'SELECT 1;' query added 3x to the SQL trace"
}

auto_interleave_failing_sql(){
  # sql interleave function based on actual input file size
  INPUTLINECOUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.backup | wc -l`
  FAILING_SQL_COUNT=`cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing | wc -l`
  if [ $FAILING_SQL_COUNT -ge 10 ]; then
    if [ $INPUTLINECOUNT -le 100 ]; then
      sed -i "0~5 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 500 ];then
      sed -i "0~25 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 1000 ];then
      sed -i "0~50 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    else
      sed -i "0~75 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    fi
  else
    if [ $INPUTLINECOUNT -le 100 ]; then
      sed -i "0~3 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 500 ];then
      sed -i "0~15 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    elif [ $INPUTLINECOUNT -le 1000 ];then
      sed -i "0~35 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    else
      sed -i "0~50 r ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing" ${INPUTFILE}
    fi
  fi
}

generate_reducer_script(){
  if [ "${BASE}" == "" ]; then 
    echo "Assert! \$BASE is empty at start of generate_reducer_script()"
    exit 1
  fi
  if [ -r ${BASE}/lib/mysql/plugin/ha_tokudb.so ]; then
    DISABLE_TOKUDB_AUTOLOAD=0
  else
    DISABLE_TOKUDB_AUTOLOAD=1
  fi
  if [ ${QC} -eq 0 ]; then
    PQUERY_EXTRA_OPTIONS="s|ZERO0|ZERO0|"
  else
    PQUERY_EXTRA_OPTIONS="0,/#VARMOD#/s|#VARMOD#|PQUERY_EXTRA_OPTIONS=\"--log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --log-query-number\"\n#VARMOD#|"
  fi
  if [ "$TEXT" == "" -o "$TEXT" == "my_print_stacktrace" -o "$TEXT" == "0" -o "$TEXT" == "NULL" ]; then  # Too general strings, or no TEXT found, use MODE=4
    MODE=4
    TEXT_CLEANUP="s|ZERO0|ZERO0|"  # A zero-effect change dummy (de-duplicates #VARMOD# code below)
    TEXT_STRING1="s|ZERO0|ZERO0|"
    TEXT_STRING2="s|ZERO0|ZERO0|"
  else  # Bug-specific TEXT string found, use MODE=3 to let reducer.sh reduce for that specific string
    if [ $VALGRIND_CHECK -eq 1 ]; then
      MODE=1
    else
      if [ ${QC} -eq 0 ]; then
        MODE=3
      else
        MODE=2
      fi
    fi
    TEXT_CLEANUP="0,/^[ \t]*TEXT[ \t]*=.*$/s|^[ \t]*TEXT[ \t]*=.*$|#TEXT=<set_below_in_machine_variables_section>|"
    TEXT_STRING1="0,/#VARMOD#/s:#VARMOD#:# IMPORTANT NOTE; Leave the 3 spaces before TEXT on the next line; pquery-results.sh uses these\n#VARMOD#:"
    if [[ "${TEXT}" = *":"* ]]; then 
      if [[ "${TEXT}" = *"|"* ]]; then 
        if [[ "${TEXT}" = *"/"* ]]; then 
          if [[ "${TEXT}" = *"_"* ]]; then 
            if [[ "${TEXT}" = *"-"* ]]; then
              echo "Assert (#1)! No suitable sed seperator found. TEXT (${TEXT}) contains all of the possibilities, add more!"
            else
              if [ ${QC} -eq 0 ]; then
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"${TEXT}\"\n#VARMOD#-"
              else
                TEXT=$(echo "$TEXT"|sed -e "s-|-\\\\\\\|-g")
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"^${TEXT}\$\"\n#VARMOD#-"
              fi
            fi
          else
            if [ ${QC} -eq 0 ]; then
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"${TEXT}\"\n#VARMOD#_"
            else
              TEXT=$(echo "$TEXT"|sed -e "s_|_\\\\\\\|_g")
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"^${TEXT}\$\"\n#VARMOD#_"
            fi
          fi
        else
          if [ ${QC} -eq 0 ]; then
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"${TEXT}\"\n#VARMOD#/"
          else
            TEXT=$(echo "$TEXT"|sed -e "s/|/\\\\\\\|/g")
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"^${TEXT}\$\"\n#VARMOD#/"
          fi
        fi
      else
        if [ ${QC} -eq 0 ]; then
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"${TEXT}\"\n#VARMOD#|"
        else
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"^${TEXT}\$\"\n#VARMOD#|"
        fi
      fi
    else
      if [ ${QC} -eq 0 ]; then
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"${TEXT}\"\n#VARMOD#:"
      else
        TEXT=$(echo "$TEXT"|sed -e "s:|:\\\\\\\|:g")
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"^${TEXT}\"\n#VARMOD#:"
      fi
    fi
  fi
  if [ "$MYEXTRA" == "" ]; then  # Empty MYEXTRA string
    MYEXTRA_CLEANUP="s|ZERO0|ZERO0|"
    MYEXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  else  # MYEXTRA specifically set
    MYEXTRA_CLEANUP="0,/^[ \t]*MYEXTRA[ \t]*=.*$/s|^[ \t]*MYEXTRA[ \t]*=.*$|#MYEXTRA=<set_below_in_machine_variables_section>|"
    if [[ "${MYEXTRA}" = *":"* ]]; then 
      if [[ "${MYEXTRA}" = *"|"* ]]; then 
        if [[ "${MYEXTRA}" = *"!"* ]]; then 
          echo "Assert! No suitable sed seperator found. MYEXTRA (${MYEXTRA}) contains all of the possibilities, add more!"
        else
          MYEXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#!"
        fi
      else
        MYEXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#|"
      fi
    else
      MYEXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#:"
    fi
  fi
  if [ "$WSREP_PROVIDER_OPTIONS" == "" ]; then  # Empty MYEXTRA string
    WSREP_OPT_CLEANUP="s|ZERO0|ZERO0|"
    WSREP_OPT_STRING="s|ZERO0|ZERO0|"  # Idem as above
  else
    WSREP_OPT_CLEANUP="0,/^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$/s|^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$|#WSREP_PROVIDER_OPTIONS=<set_below_in_machine_variables_section>|"
    WSREP_OPT_STRING="0,/#VARMOD#/s:#VARMOD#:WSREP_PROVIDER_OPTIONS=\"${WSREP_PROVIDER_OPTIONS}\"\n#VARMOD#:"
  fi
  if [ "$MULTI" != "1" ]; then  # Not a multi-threaded pquery run
    MULTI_CLEANUP="s|ZERO0|ZERO0|"  # Idem as above
    MULTI_CLEANUP2="s|ZERO0|ZERO0|"
    MULTI_CLEANUP3="s|ZERO0|ZERO0|"
    MULTI_STRING1="s|ZERO0|ZERO0|"
    MULTI_STRING2="s|ZERO0|ZERO0|"
    MULTI_STRING3="s|ZERO0|ZERO0|"
  else  # Multi-threaded pquery run
    MULTI_CLEANUP1="0,/^[ \t]*PQUERY_MULTI[ \t]*=.*$/s|^[ \t]*PQUERY_MULTI[ \t]*=.*$|#PQUERY_MULTI=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP2="0,/^[ \t]*FORCE_SKIPV[ \t]*=.*$/s|^[ \t]*FORCE_SKIPV[ \t]*=.*$|#FORCE_SKIPV=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP3="0,/^[ \t]*FORCE_SPORADIC[ \t]*=.*$/s|^[ \t]*FORCE_SPORADIC[ \t]*=.*$|#FORCE_SPORADIC=<set_below_in_machine_variables_section>|"
    MULTI_STRING1="0,/#VARMOD#/s:#VARMOD#:PQUERY_MULTI=1\n#VARMOD#:"
    MULTI_STRING2="0,/#VARMOD#/s:#VARMOD#:FORCE_SKIPV=1\n#VARMOD#:"
    MULTI_STRING3="0,/#VARMOD#/s:#VARMOD#:FORCE_SPORADIC=1\n#VARMOD#:"
  fi
  if [ ${PXC} -eq 1 ]; then
    PXC_CLEANUP1="0,/^[ \t]*PXC_MOD[ \t]*=.*$/s|^[ \t]*PXC_MOD[ \t]*=.*$|#PXC_MOD=<set_below_in_machine_variables_section>|"
    PXC_STRING1="0,/#VARMOD#/s:#VARMOD#:PXC_MOD=1\n#VARMOD#:"
  else
    PXC_CLEANUP1="s|ZERO0|ZERO0|"  # Idem as above
    PXC_STRING1="s|ZERO0|ZERO0|"
  fi
  if [ ${QC} -eq 0 ]; then
    REDUCER_FILENAME=reducer${OUTFILE}.sh
    QC_STRING1="s|ZERO0|ZERO0|"
    QC_STRING2="s|ZERO0|ZERO0|"
    QC_STRING3="s|ZERO0|ZERO0|"
    QC_STRING4="s|ZERO0|ZERO0|"
  else
    REDUCER_FILENAME=qcreducer${OUTFILE}.sh
    QC_STRING1="s|CURRENTLINE=2|CURRENTLINE=5|g"
    QC_STRING2="s|REALLINE=2|REALLINE=5|g"
    QC_STRING3="0,/#VARMOD#/s:#VARMOD#:QCTEXT=\"${QCTEXT}\"\n#VARMOD#:"
    QC_STRING4="s|SKIPSTAGEABOVE=9|SKIPSTAGEABOVE=3|"
  fi
  cat ${REDUCER} \
   | sed -e "0,/^[ \t]*INPUTFILE[ \t]*=.*$/s|^[ \t]*INPUTFILE[ \t]*=.*$|#INPUTFILE=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*MODE[ \t]*=.*$/s|^[ \t]*MODE[ \t]*=.*$|#MODE=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$/s|^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$|#DISABLE_TOKUDB_AUTOLOAD=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$/s|^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$|#PQUERY_EXTRA_OPTIONS=<set_below_in_machine_variables_section>|" \
   | sed -e "${MYEXTRA_CLEANUP}" \
   | sed -e "${WSREP_OPT_CLEANUP}" \
   | sed -e "${TEXT_CLEANUP}" \
   | sed -e "${MULTI_CLEANUP1}" \
   | sed -e "${MULTI_CLEANUP2}" \
   | sed -e "${MULTI_CLEANUP3}" \
   | sed -e "0,/^[ \t]*MYBASE[ \t]*=.*$/s|^[ \t]*MYBASE[ \t]*=.*$|#MYBASE=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*PQUERY_MOD[ \t]*=.*$/s|^[ \t]*PQUERY_MOD[ \t]*=.*$|#PQUERY_MOD=<set_below_in_machine_variables_section>|" \
   | sed -e "0,/^[ \t]*PQUERY_LOC[ \t]*=.*$/s|^[ \t]*PQUERY_LOC[ \t]*=.*$|#PQUERY_LOC=<set_below_in_machine_variables_section>|" \
   | sed -e "${PXC_CLEANUP1}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:MODE=${MODE}\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:DISABLE_TOKUDB_AUTOLOAD=${DISABLE_TOKUDB_AUTOLOAD}\n#VARMOD#:" \
   | sed -e "${TEXT_STRING1}" \
   | sed -e "${TEXT_STRING2}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:MYBASE=\"${BASE}\"\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:INPUTFILE=\"${INPUTFILE}\"\n#VARMOD#:" \
   | sed -e "${MYEXTRA_STRING1}" \
   | sed -e "${WSREP_OPT_STRING}" \
   | sed -e "${MULTI_STRING1}" \
   | sed -e "${MULTI_STRING2}" \
   | sed -e "${MULTI_STRING3}" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:PQUERY_MOD=1\n#VARMOD#:" \
   | sed -e "0,/#VARMOD#/s:#VARMOD#:PQUERY_LOC=${PQUERY_BIN}\n#VARMOD#:" \
   | sed -e "${PXC_STRING1}" \
   | sed -e "${QC_STRING1}" \
   | sed -e "${QC_STRING2}" \
   | sed -e "${QC_STRING3}" \
   | sed -e "${QC_STRING4}" \
   | sed -e "${PQUERY_EXTRA_OPTIONS}" \
   > ${REDUCER_FILENAME}
  chmod +x ${REDUCER_FILENAME}
}

# Main pquery results processing
if [ ${QC} -eq 0 ]; then
  if [ ${PXC} -eq 1 ]; then
    for TRIAL in $(ls ./*/node*/core* 2>/dev/null | sed 's|./||;s|/.*||' | sort | uniq); do
      for SUBDIR in `ls -lt ${TRIAL} --time-style="long-iso"  | egrep '^d'  | awk '{print $8}' | tr -dc '0-9\n' | sort`; do
        OUTFILE="${TRIAL}-${SUBDIR}"
        rm -Rf  ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        touch ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        echo "========== Processing pquery trial ${TRIAL}-${SUBDIR}"
        if [ -r ./reducer${TRIAL}-${SUBDIR}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}_${SUBDIR}.sh) already exists. Skipping to next trial."
          continue
        fi
        if [ ${NEW_MYEXTRA_METHOD} -eq 1 ]; then
          MYEXTRA=$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)
        fi
        if [ ${WSREP_OPTION_CHECK} -eq 1 ]; then
          WSREP_PROVIDER_OPTIONS=$(cat ./${TRIAL}/WSREP_PROVIDER_OPT 2>/dev/null)
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}.sql
          cp ${INPUTFILE} ${INPUTFILE}.backup
        else
          if [ $(ls -1 ./${TRIAL}/*thread-0.sql 2>/dev/null|wc -l) -gt 1 ]; then
            INPUTFILE=$(ls ./${TRIAL}/node`expr ${SUBDIR} - 1`*thread-0.sql)
          elif [ -f ./${TRIAL}/*thread-0.sql ] ; then
            INPUTFILE=`ls ./${TRIAL}/*thread-0.sql | sed "s|^[./]\+|/|;s|^|${WORKD_PWD}|"`
          else
            INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}-${SUBDIR}.sql
          fi
        fi
        BIN=`ls -1 ${WORKD_PWD}/${TRIAL}/node${SUBDIR}/mysqld 2>&1 | head -n1 | grep -v "No such file"`
        if [ ! -r $BIN ]; then
          echo "Assert! mysqld binary '$BIN' could not be read"
          exit 1
        fi
        if [ `ls ./pquery-run.log 2>/dev/null | wc -l` -eq 0 ]; then
          BASE="/sda/Percona-Server-5.6.21-rel70.0-696.Linux.x86_64-debug"  # Should never really happen, but just in case, so that something "is there"? Needs review.
        else
          BASE="`grep 'Basedir:' ./pquery-run.log | sed 's|^.*Basedir[: \t]*||;;s/|.*$//' | tr -d '[[:space:]]'`"
        fi
        CORE=`ls -1 ./${TRIAL}/node${SUBDIR}/*core* 2>&1 | head -n1 | grep -v "No such file"`
        ERRLOG=./${TRIAL}/node${SUBDIR}/node${SUBDIR}.err
        if [ `cat ${INPUTFILE} | wc -l` -ne 0 ]; then
          if [ "$CORE" != "" ]; then
            extract_queries_core
          fi
          if [ "$ERRLOG" != "" ]; then
            extract_queries_error_log
          else
            echo "Assert! Error log at ./${TRIAL}/node${SUBDIR}/error.log could not be read?"
            exit 1
          fi
        fi
        add_select_ones_to_trace
        TEXT=`${SCRIPT_PWD}/text_string.sh ./${TRIAL}/node${SUBDIR}/node${SUBDIR}.err`
        echo "* TEXT variable set to: \"${TEXT}\""
        if [ "${MULTI}" == "1" ]; then
           if [ -s ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing ];then
             auto_interleave_failing_sql
           fi
        fi
        generate_reducer_script
      done
      if [ "${MYEXTRA}" != "" ]; then
        echo "* MYEXTRA variable set to: ${MYEXTRA}"
      fi
      if [ "${WSREP_PROVIDER_OPTIONS}" != "" ]; then
        echo "* WSREP_PROVIDER_OPTIONS variable set to: ${WSREP_PROVIDER_OPTIONS}"
      fi
      if [ ${VALGRIND_CHECK} -eq 1 ]; then
        echo "* Valgrind was used for this trial"
      fi
    done
  else
    for SQLLOG in $(ls ./*/*thread-0.sql 2>/dev/null); do
      TRIAL=`echo ${SQLLOG} | sed 's|./||;s|/.*||'`
      if [ ${NEW_MYEXTRA_METHOD} -eq 1 ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)
      fi
      if [ ${PXC} -eq 0 ]; then
        OUTFILE=$TRIAL
        rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        touch ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
        if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
          echo "========== Processing pquery trial $TRIAL"
        fi
        if [ ! -r ./${TRIAL}/start ]; then
          echo "* No ./${TRIAL}/start detected, so this was likely a SAVE_SQL=1, SAVE_TRIALS_WITH_CORE_ONLY=1 trial with no core generated. Skipping to next trial."
          continue
        fi
        if [ -r ./reducer${TRIAL}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}.sh) already exists. Skipping to next trial."
          continue
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${WORKD_PWD}/${TRIAL}/${TRIAL}.sql
          cp ${INPUTFILE} ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.backup
        else
          INPUTFILE=`echo ${SQLLOG} | sed "s|^[./]\+|/|;s|^|${WORKD_PWD}|"`
        fi
        BIN=$(grep "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|') 
        if [ "${BIN}" == "" ]; then 
          echo "Assert \$BIN is empty"
          exit 1
        fi
        if [ ! -r "${BIN}" ]; then
          echo "Assert! mysqld binary '${BIN}' could not be read"
          exit 1
        fi
        BASE=`echo ${BIN} | sed 's|/bin/mysqld||'`
        if [ ! -d "${BASE}" ]; then
          echo "Assert! Basedir '${BASE}' does not look to be a directory"
          exit 1
        fi
        CORE=`ls -1 ./${TRIAL}/data/*core* 2>&1 | head -n1 | grep -v "No such file"`
        if [ "$CORE" != "" ]; then
          extract_queries_core
        fi
        ERRLOG=./${TRIAL}/log/master.err
        if [ "$ERRLOG" != "" ]; then
          extract_queries_error_log
        else
          echo "Assert! Error log at ./${TRIAL}/log/master.err could not be read?"
          exit 1
        fi
        add_select_ones_to_trace
        VALGRIND_CHECK=0
        VALGRIND_ERRORS_FOUND=0; VALGRIND_CHECK_1=
        if [ -r ./${TRIAL}/VALGRIND -a ${VALGRIND_OVERRIDE} -ne 1 ]; then
          VALGRIND_CHECK=1
          # What follows are 3 different ways of checking if Valgrind issues were seen, mostly to ensure that no Valgrind issues go unseen, especially if log is not complete
          VALGRIND_CHECK_1=$(grep "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ./${TRIAL}/log/master.err | sed 's|.*ERROR SUMMARY: \([0-9]\+\) error.*|\1|')
          if [ "${VALGRIND_CHECK_1}" == "" ]; then VALGRIND_CHECK_1=0; fi
          if [ ${VALGRIND_CHECK_1} -gt 0 ]; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep -qi "^[ \t]*==[0-9]+[= \t]+[atby]+[ \t]*0x" ./${TRIAL}/log/master.err; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep -qi "==[0-9]+== ERROR SUMMARY: [1-9]" ./${TRIAL}/log/master.err; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if [ ${VALGRIND_ERRORS_FOUND} -eq 1 ]; then
            TEXT=`${SCRIPT_PWD}/valgrind_string.sh ./${TRIAL}/log/master.err`
            if [ "${TEXT}" != "" ]; then
              echo "* Valgrind string detected: '${TEXT}'"
            else
              echo "*** ERROR: No specific Valgrind string was detected in ./${TRIAL}/log/master.err! This may be a bug... Setting TEXT to generic '==    at 0x'"
              TEXT="==    at 0x"
            fi
            # generate a valgrind specific reducer and then reset values if standard crash reducer is needed
            OUTFILE=_val$TRIAL
            generate_reducer_script
            VALGRIND_CHECK=0
            OUTFILE=$TRIAL
          fi
        fi
        # if not a valgrind run process everything, if it is valgrind run only if there's a core
        if [ ! -r ./${TRIAL}/VALGRIND ] || [ -r ./${TRIAL}/VALGRIND -a "$CORE" != "" ]; then
          TEXT=`${SCRIPT_PWD}/text_string.sh ./${TRIAL}/log/master.err`
          echo "* TEXT variable set to: \"${TEXT}\""
          if [ "${MULTI}" == "1" -a -s ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing ];then
            auto_interleave_failing_sql
          fi
          generate_reducer_script
        fi
      fi
      if [ "${MYEXTRA}" != "" ]; then
        echo "* MYEXTRA variable set to: ${MYEXTRA}"
      fi
      if [ ${VALGRIND_CHECK} -eq 1 ]; then
        echo "* Valgrind was used for this trial"
      fi
    done
  fi
else
  for TRIAL in $(ls ./*/diff.result 2>/dev/null | sed 's|./||;s|/.*||'); do
    BIN=$(grep "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|') 
    if [ "${BIN}" == "" ]; then 
      echo "Assert \$BIN is empty"
      exit 1
    fi
    if [ ! -r "${BIN}" ]; then
      echo "Assert! mysqld binary '${BIN}' could not be read"
      exit 1
    fi
    BASE=`echo ${BIN} | sed 's|/bin/mysqld||'`
    if [ ! -d "${BASE}" ]; then
      echo "Assert! Basedir '${BASE}' does not look to be a directory"
      exit 1
    fi
    TEXT=$(grep "^[<>]" ./${TRIAL}/diff.result | awk '{print length, $0;}' | sort -nr | head -n1 | sed 's/^[0-9]\+[ \t]\+//')
    LEFTRIGHT=$(echo ${TEXT} | sed 's/\(^.\).*/\1/')
    TEXT=$(echo ${TEXT} | sed 's/[<>][ \t]\+//')
    ENGINE=
    FAULT=0
    # Pre-processing all possible sql files to make it suitable for reducer.sh and manual replay - this can be handled in pquery core < TODO
    sed -i "s/;|NOERROR/;#NOERROR/" ${WORKD_PWD}/${TRIAL}/*_thread-0.*.sql
    sed -i "s/;|ERROR/;#ERROR/" ${WORKD_PWD}/${TRIAL}/*_thread-0.*.sql
    if [ "${LEFTRIGHT}" == "<" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.left)
      MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.left 2>/dev/null)
    elif [ "${LEFTRIGHT}" == ">" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.right)
      MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.right 2>/dev/null)
    else
      # Possible reasons for this can be: interrupted or crashed trial, ... ???
      echo "Warning! \$LEFTRIGHT != '<' or '>' but '${LEFTRIGHT}' for trial ${TRIAL}! NOTE: qcreducer${TRIAL}.sh will not be complete: renaming to qcreducer${TRIAL}_notcomplete.sh!"
      FAULT=1
    fi
    if [ ${FAULT} -ne 1 ]; then
      QCTEXTLN=$(echo "${TEXT}" | grep -o "[0-9]*$")
      TEXT=$(echo ${TEXT} | sed "s/#[0-9]*$//")
      QCTEXT=$(sed -n "${QCTEXTLN},${QCTEXTLN}p" ${WORKD_PWD}/${TRIAL}/*_thread-0.${ENGINE}.sql | grep -o "#@[0-9]*#")
    fi
    # Output of the following is too verbose
    #if [ "${MYEXTRA}" != "" ]; then
    #  echo "* MYEXTRA variable set to: ${MYEXTRA}"
    #fi
    INPUTFILE=$(echo ${TRIAL} | sed "s|^|${WORKD_PWD}/|" | sed "s|$|/*_thread-0.${ENGINE}.sql|")
    echo "* Query Correctness: Data Correctness (QC DC) TEXT variable for trial ${TRIAL} set to: \"${TEXT}\""
    echo "* Query Correctness: Line Identifier (QC LI) QCTEXT variable for trial ${TRIAL} set to: \"${QCTEXT}\""
    OUTFILE=$TRIAL
    generate_reducer_script
    if [ ${FAULT} -eq 1 ]; then
      mv ./qcreducer${TRIAL}.sh ./qcreducer${TRIAL}_notcomplete.sh
    fi
  done
fi

if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
  echo "======================================================================================================================================================"
  if [ ${QC} -eq 0 ]; then
    echo -e "\nDone!! Start reducer scripts like this: './reducerTRIAL.sh' or './reducer_valTRIAL.sh' where TRIAL stands for the trial number you would like to reduce"
    echo "Both reducer and the SQL trace file have been pre-prepped with all the crashing queries and settings, ready for you to use without further options!"
  else
    echo -e "\nDone!! Start reducer scripts like this: './qcreducerTRIAL.sh' where TRIAL stands for the trial number you would like to reduce"
  fi
  echo -e "\nIMPORTANT!! Remember that settings pre-programmed into reducerTRIAL.sh by this script are in the 'Machine configurable variables' section, not"
  echo "in the 'User configurable variables' section. As such, and for example, if you want to change the settings (for example change MODE=3 to MODE=4), then"
  echo "please make such changes in the 'Machine configurable variables' section which is a bit lower in the file (search for 'Machine' to find it easily)."
  echo "Any changes you make in the 'User configurable variables' section will not take effect as the Machine sections overwrites these!"
  echo -e "\nIMPORTANT!! Remember that a number of testcases as generated by reducer.sh will require the MYEXTRA mysqld options used in the original test."
  echo "The reducer<nr>.sh scripts already have these set, but when you want to replay a testcase in some other mysqld setup, remember you will need these"
  echo "options passed to mysqld directly or in some my.cnf script. Note also, in reverse, that the presence of certain mysqld options that did not form part"
  echo "of the original test can cause the same effect; non-reproducibility of the testcase. You want a replay setup as closely matched as possible. If you"
  echo "use the new scripts (./{epoch}_init, _start, _stop, _cl, _run, _run-pquery, _stop etc. then these options for mysqld will already be preset for you."
fi
