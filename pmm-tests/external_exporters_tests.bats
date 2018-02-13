#!/usr/bin/env bats

@test "Checking consul_exporter" {
  IP_ADDRESS=$(ip route get 1 | awk '{print $NF;exit}')
  run bash -c "curl -s "http://${IP_ADDRESS}:9107/metrics" | grep '^consul_'"
  echo "$output"
  [ "$status" -eq 0 ]
  echo  "${lines[1]}" | grep  "consul_up"
}