# Sourced by the archive scripts. `need CMD...` checks that each command
# exists; if any is missing it says which and how to install them, waits for
# Enter (popups close as soon as their script exits), and exits 1.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

need() {
  missing=
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
  done
  [ -z "$missing" ] && return 0
  printf 'Missing:%s\n\n' "$missing"
  pkgs=$(for c in $missing; do [ "$c" = rex ] || echo "$c"; done | tr '\n' ' ' | sed 's/ *$//')
  [ -n "$pkgs" ] && printf 'Install with:\n  brew install %s\n' "$pkgs"
  case " $missing " in
    *" rex "*) printf '\nrex comes with the Rex app. Run this from a Rex terminal.\n' ;;
  esac
  printf '\nPress Enter to close. '
  read -r _
  exit 1
}
