#!/usr/bin/env bats

# Created by Shahriyar Rzayev from Percona

# Check audit_log_include_accounts option

DIRNAME=$BATS_TEST_DIRNAME
WORKDIR="${PWD}"

BASEDIR=$(ls -1td ${WORKDIR}/PS* | grep -v ".tar" | grep PS[0-9])
CONN=$(cat ${BASEDIR}/cl_noprompt)

@test "running test for audit_log_include_accounts='audited_user@localhost'" {
  # First setting to NULL
  $($CONN -e "set global audit_log_include_accounts=null")
  # Create dummy user
  $($CONN -e "create user audited_user@localhost identified by 'Baku12345#'")
  $($CONN -e "grant all on *.* to audited_user@localhost")
  # Enable here
  $($CONN -e "set global audit_log_include_accounts='audited_user@localhost'")
  # Running dummy SQL
  sql=$(${CONN} --user=audited_user --password='Baku12345#' -e "select @@innodb_buffer_pool_size")
  # Checking audit.log file
  result="$(cat ${BASEDIR}/data/audit.log | grep 'select @@innodb_buffer_pool_size')"
  echo $result | grep 'audited_user'
}