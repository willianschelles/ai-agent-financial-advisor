#!/bin/bash
for line in (cat .env)
  set -l key (echo $line | cut -d '=' -f 1)
  set -l val (echo $line | cut -d '=' -f 2-)
  set -gx $key $val
end

