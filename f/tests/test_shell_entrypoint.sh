#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entry="${project_dir}/yu.sh"

bash -n "${entry}"
help_output="$(bash "${entry}" --help)"

for expected in \
  './yu.sh setup' \
  './yu.sh 1-4 --resume' \
  '--analysis-project' \
  '--path-prompt-mode'
do
  if [[ "${help_output}" != *"${expected}"* ]]; then
    printf 'Missing shell help contract: %s\n' "${expected}" >&2
    exit 1
  fi
done

if bash "${entry}" --unknown-option >/dev/null 2>&1; then
  printf 'Unknown shell options must fail.\n' >&2
  exit 1
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT
capture_file="${fixture_dir}/args.txt"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "${YU_SHELL_CAPTURE}"' \
  > "${fixture_dir}/powershell.exe"
chmod +x "${fixture_dir}/powershell.exe"

PATH="${fixture_dir}:${PATH}" YU_SHELL_CAPTURE="${capture_file}" \
  bash "${entry}" 1-4 --resume --workers 16

for expected in '-Step' '1-4' '-Resume' '-Workers' '16'; do
  if ! grep -Fxq -- "${expected}" "${capture_file}"; then
    printf 'Shell argument forwarding failed: %s\n' "${expected}" >&2
    exit 1
  fi
done

printf 'YU SHELL ENTRYPOINT TEST PASSED\n'
