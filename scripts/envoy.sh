#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-}"
shift || true

usage() {
  cat <<EOF
helm-envoy — environment-aware Helm value file manager

Usage:
  helm envoy install <release> <chart> --environment <env> [-- <helm flags>]
  helm envoy upgrade <release> <chart> --environment <env> [-- <helm flags>]
  helm envoy list-environments <chart-path>

Flags:
  --environment <env>     Environment name to resolve value files for
  --list-environments     Alias: list environments for the given chart path

Value file resolution order (all that exist are applied, low to high priority):
  values.yaml
  values-<env>.yaml
  values-<env>.local.yaml  (gitignored overrides, if present)

Examples:
  helm envoy install my-app ./chart --environment production
  helm envoy upgrade my-app ./chart --environment staging -- --atomic --timeout 5m
  helm envoy list-environments ./chart
EOF
}

# Find all environment value files in a chart directory.
# Looks for files matching: values-<something>.yaml
find_env_value_files() {
  local chart_path="$1"
  find "$chart_path" -maxdepth 1 -name "values-*.yaml" \
    | sed 's|.*/values-||' \
    | sed 's|\.yaml$||' \
    | sort -u
}

list_environments() {
  local chart_path="${1:-.}"

  if [[ ! -d "$chart_path" ]]; then
    echo "Error: chart path '$chart_path' is not a directory." >&2
    exit 1
  fi

  local envs
  envs=$(find_env_value_files "$chart_path")

  if [[ -z "$envs" ]]; then
    echo "No environment value files found in '$chart_path'."
    echo "Expected files named: values-<environment>.yaml"
  else
    echo "Environments found in '$chart_path':"
    while IFS= read -r env; do
      local file="$chart_path/values-${env}.yaml"
      echo "  - $env  ($file)"
    done <<< "$envs"
  fi
}

build_value_file_args() {
  local chart_path="$1"
  local env="$2"
  local args=()

  local base_values="$chart_path/values.yaml"
  if [[ -f "$base_values" ]]; then
    args+=("-f" "$base_values")
  fi

  local env_values="$chart_path/values-${env}.yaml"
  if [[ ! -f "$env_values" ]]; then
    echo "Error: no value file found for environment '${env}'." >&2
    echo "Expected: $env_values" >&2
    echo "" >&2
    echo "Available environments:" >&2
    find_env_value_files "$chart_path" | sed 's/^/  - /' >&2
    exit 1
  fi
  args+=("-f" "$env_values")

  local local_values="$chart_path/values-${env}.local.yaml"
  if [[ -f "$local_values" ]]; then
    args+=("-f" "$local_values")
  fi

  echo "${args[@]+"${args[@]}"}"
}

run_helm_command() {
  local helm_cmd="$1"   # install | upgrade
  local release="$2"
  local chart="$3"
  shift 3

  local environment=""
  local extra_args=()
  local passthrough=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --environment)
        environment="$2"
        shift 2
        ;;
      --)
        passthrough=true
        shift
        ;;
      *)
        if $passthrough; then
          extra_args+=("$1")
        else
          extra_args+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$environment" ]]; then
    echo "Error: --environment <name> is required." >&2
    echo "Use 'helm envoy list-environments <chart>' to see available environments." >&2
    exit 1
  fi

  local chart_path
  # Resolve chart path for local charts; skip for repo charts (no slash/dot prefix)
  if [[ "$chart" == .* || "$chart" == /* ]]; then
    chart_path="$chart"
  else
    chart_path="."
  fi

  local value_args
  read -ra value_args <<< "$(build_value_file_args "$chart_path" "$environment")"

  echo "helm-envoy: running helm $helm_cmd for environment '$environment'"
  echo "  release : $release"
  echo "  chart   : $chart"
  echo "  values  : ${value_args[*]+"${value_args[*]}"}"
  [[ ${#extra_args[@]} -gt 0 ]] && echo "  flags   : ${extra_args[*]}"
  echo ""

  helm "$helm_cmd" "$release" "$chart" "${value_args[@]+"${value_args[@]}"}" "${extra_args[@]+"${extra_args[@]}"}"
}

case "$COMMAND" in
  install)
    run_helm_command "install" "$@"
    ;;
  upgrade)
    run_helm_command "upgrade" "$@"
    ;;
  list-environments|--list-environments)
    list_environments "${1:-.}"
    ;;
  help|--help|-h|"")
    usage
    ;;
  *)
    echo "Error: unknown command '$COMMAND'." >&2
    echo "" >&2
    usage
    exit 1
    ;;
esac
