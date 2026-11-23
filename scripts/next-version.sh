#!/usr/bin/env zsh
set -euo pipefail

BUMP="auto"
LATEST_TAG=""
HAS_LATEST_TAG_OVERRIDE=false
COMMITS=""
HAS_COMMITS_OVERRIDE=false

usage() {
  echo "Usage: $0 [--bump <auto|patch|minor|major>] [--latest-tag <tag>] [--commits <text>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      if [[ $# -lt 2 ]]; then
        echo "Error: --bump requires a value" >&2
        usage
        exit 1
      fi
      BUMP="$2"
      shift 2
      ;;
    --latest-tag)
      if [[ $# -lt 2 ]]; then
        echo "Error: --latest-tag requires a value" >&2
        usage
        exit 1
      fi
      LATEST_TAG="$2"
      HAS_LATEST_TAG_OVERRIDE=true
      shift 2
      ;;
    --commits)
      if [[ $# -lt 2 ]]; then
        echo "Error: --commits requires a value" >&2
        usage
        exit 1
      fi
      COMMITS="$2"
      HAS_COMMITS_OVERRIDE=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$BUMP" in
  auto|patch|minor|major) ;;
  *)
    echo "Error: Unsupported bump mode '$BUMP' (expected auto, patch, minor, or major)" >&2
    usage
    exit 1
    ;;
esac

if [[ "$HAS_LATEST_TAG_OVERRIDE" == false ]]; then
  LATEST_TAG="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | head -n 1)"
fi

if [[ -z "$LATEST_TAG" ]]; then
  case "$BUMP" in
    major) printf '%s\n' "1.0.0" ;;
    minor) printf '%s\n' "0.1.0" ;;
    auto|patch) printf '%s\n' "0.0.1" ;;
  esac
  exit 0
fi

RAW_VERSION="${LATEST_TAG#v}"
if ! [[ "$RAW_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Error: Invalid tag format '$LATEST_TAG' (expected vMAJOR.MINOR.PATCH)" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$RAW_VERSION"
MAJOR=$((10#$MAJOR))
MINOR=$((10#$MINOR))
PATCH=$((10#$PATCH))

case "$BUMP" in
  major)
    printf '%s\n' "$((MAJOR + 1)).0.0"
    exit 0
    ;;
  minor)
    printf '%s\n' "${MAJOR}.$((MINOR + 1)).0"
    exit 0
    ;;
  patch)
    printf '%s\n' "${MAJOR}.${MINOR}.$((PATCH + 1))"
    exit 0
    ;;
esac

if [[ "$HAS_COMMITS_OVERRIDE" == false ]]; then
  COMMITS="$(git log "${LATEST_TAG}..HEAD" --format='%s%n%b')"
fi

HAS_BREAKING=false
if grep -Eq '^[a-zA-Z0-9_-]+(\([^)]*\))?!:|BREAKING[ -]CHANGE:' <<< "$COMMITS"; then
  HAS_BREAKING=true
fi

HAS_FEAT=false
if grep -Eq '^feat(\([^)]*\))?!?:' <<< "$COMMITS"; then
  HAS_FEAT=true
fi

if [[ "$MAJOR" -eq 0 ]]; then
  if [[ "$HAS_BREAKING" == true || "$HAS_FEAT" == true ]]; then
    printf '%s\n' "0.$((MINOR + 1)).0"
  else
    printf '%s\n' "0.${MINOR}.$((PATCH + 1))"
  fi
else
  if [[ "$HAS_BREAKING" == true ]]; then
    printf '%s\n' "$((MAJOR + 1)).0.0"
  elif [[ "$HAS_FEAT" == true ]]; then
    printf '%s\n' "${MAJOR}.$((MINOR + 1)).0"
  else
    printf '%s\n' "${MAJOR}.${MINOR}.$((PATCH + 1))"
  fi
fi
