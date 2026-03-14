#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_script="$script_dir/grazing_ppe_script_niter_input.sh"

if [[ ! -f "$target_script" ]]; then
    echo "Error: target script not found: $target_script"
    exit 1
fi

for niter in {3..5}; do
    echo "Running with niter=$niter"
    bash "$target_script" "$niter"
done

echo "Completed niter loop 0..5"
