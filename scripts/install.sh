#!/usr/bin/env bash
# DDB Skillhub installer for macOS and Linux.
#
#   ./scripts/install.sh list
#   ./scripts/install.sh install --all
#   ./scripts/install.sh install pdf-table-extract
#   ./scripts/install.sh uninstall pdf-table-extract
#
# It installs into ~/.agents/skills/<name>, which is where DeepSeek Harness and
# other agent runtimes look for skills.
set -euo pipefail

REPO_SLUG="${DDB_SKILLHUB_REPO:-Didib-Lab/didib-skillhub}"
REF="${DDB_SKILLHUB_REF:-main}"
SKILLS_DIR="${DDB_SKILLHUB_DEST:-$HOME/.agents/skills}"
API="https://api.github.com/repos/$REPO_SLUG/contents/skills?ref=$REF"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"
}

# Print the skill names available in the remote repository.
remote_names() {
  need_cmd curl
  curl -fsSL "$API" \
    | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

# Print "name<TAB>description" for each advertised skill.
cmd_list() {
  need_cmd curl
  local names
  names="$(remote_names)" || die "cannot reach github.com (check your network)"
  [ -n "$names" ] || die "no skills found in $REPO_SLUG@$REF"

  printf 'Available skills in %s@%s\n\n' "$REPO_SLUG" "$REF"
  local name desc
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    desc="$(curl -fsSL \
      "https://raw.githubusercontent.com/$REPO_SLUG/$REF/skills/$name/SKILL.md" \
      | sed -n 's/^description:[[:space:]]*//p' | head -n 1 | cut -c1-100)"
    printf '  %-28s %s\n' "$name" "${desc:-（no description）}"
  done <<< "$names"
}

# Download and unpack one skill into $SKILLS_DIR.
cmd_install_one() {
  local name="$1"
  [ -n "$name" ] || die "usage: install.sh install <skill-name>|--all"

  case "$name" in
    *[!a-z0-9-]*|'') die "invalid skill name '$name' (kebab-case only)" ;;
  esac

  local dest="$SKILLS_DIR/$name"
  if [ -e "$dest" ]; then
    die "$dest already exists; run 'install.sh uninstall $name' first"
  fi

  local url="https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REF"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  info "fetching $REPO_SLUG@$REF ..."
  curl -fsSL "$url" | tar -xz -C "$tmp" || die "download failed"

  # The archive always unpacks into a single top-level directory whose name is
  # derived from the repository and ref, so locate it rather than assume it.
  local repo_root
  repo_root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -n "$repo_root" ] || die "the downloaded archive was empty"

  local src="$repo_root/skills/$name"
  [ -d "$src" ] || die "skill '$name' does not exist in $REPO_SLUG"

  mkdir -p "$SKILLS_DIR"
  cp -R "$src" "$SKILLS_DIR/"
  info "installed '$name' -> $dest"
}

cmd_install() {
  local target="${1:---all}"
  if [ "$target" = "--all" ]; then
    local name
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      cmd_install_one "$name" || info "skipped '$name'"
    done <<< "$(remote_names)"
  else
    cmd_install_one "$target"
  fi
}

cmd_uninstall() {
  local name="${1:-}"
  [ -n "$name" ] || die "usage: install.sh uninstall <skill-name>"
  local dest="$SKILLS_DIR/$name"
  [ -d "$dest" ] || die "$dest does not exist"
  rm -rf "$dest"
  info "removed $dest"
}

cmd_doctor() {
  info "skills directory: $SKILLS_DIR"
  [ -d "$SKILLS_DIR" ] || { info "  (does not exist yet)"; return 0; }
  local found=0 dir
  for dir in "$SKILLS_DIR"/*/; do
    [ -d "$dir" ] || continue
    found=$((found + 1))
    if [ -f "$dir/SKILL.md" ]; then
      printf '  ok    %s\n' "$(basename "$dir")"
    else
      printf '  BROKEN %s (no SKILL.md)\n' "$(basename "$dir")"
    fi
  done
  [ "$found" -gt 0 ] || info "  (no skills installed)"
}

usage() {
  cat <<'EOF'
DDB Skillhub installer

Usage:
  install.sh list                       list skills available in the hub
  install.sh install <name>             install one skill
  install.sh install --all              install every skill
  install.sh uninstall <name>           remove an installed skill
  install.sh doctor                     show what is installed locally

Environment:
  DDB_SKILLHUB_REPO   owner/repo to install from (default Didib-Lab/didib-skillhub)
  DDB_SKILLHUB_REF    git ref to install from   (default main)
  DDB_SKILLHUB_DEST   install target            (default ~/.agents/skills)
EOF
}

case "${1:-}" in
  list) shift; cmd_list "$@" ;;
  install) shift; cmd_install "$@" ;;
  uninstall|remove) shift; cmd_uninstall "$@" ;;
  doctor) shift; cmd_doctor "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; die "unknown command '$1'" ;;
esac
