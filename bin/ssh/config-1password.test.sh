#!/usr/bin/env bash
# Self-check for ./config-1password.sh. op and hostname are stubbed on PATH and
# HOME is a throwaway dir, so backup and restore run with no 1Password, no
# network and no touching the real ~/.ssh/config.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script=$here/config-1password.sh
fails=0

check() {
	if [ "$2" = "$3" ]; then echo "ok   $1"; else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}
contains() {
	if grep -qF -- "$3" "$2" 2>/dev/null; then echo "ok   $1"; else
		echo "FAIL $1"; echo "  $2 has no line with: $3"; fails=$((fails + 1))
	fi
}

# hostname is pinned to testbox, so the item title is deterministic. op logs
# every call to $OP_LOG, answers `item get` from $OP_ITEM_EXISTS, and on
# `document get` writes a sentinel to the --out-file so restore is observable.
setup() {
	home=$(mktemp -d)
	bin=$home/bin
	mkdir -p "$bin" "$home/.ssh"
	printf '#!/usr/bin/env bash\necho testbox\n' >"$bin/hostname"
	cat >"$bin/op" <<'OPEOF'
#!/usr/bin/env bash
echo "op $*" >>"$OP_LOG"
if [ "$1 $2" = "item get" ]; then
	[ "${OP_ITEM_EXISTS:-no}" = yes ] && exit 0 || exit 1
fi
if [ "$1 $2" = "document get" ]; then
	prev=; for a in "$@"; do [ "$prev" = "--out-file" ] && echo "RESTORED" >"$a"; prev="$a"; done
fi
exit 0
OPEOF
	chmod +x "$bin/hostname" "$bin/op"
}

# run <item-exists> <script args...>
run() { PATH="$bin:$PATH" HOME="$home" OP_LOG="$home/op.log" OP_ITEM_EXISTS="${1:-no}" \
	bash "$script" "${@:2}"; }

echo "== backup when the item does not exist yet -> create"
setup
printf 'Host x\n' >"$home/.ssh/config"
run no backup >/dev/null; check "succeeds" "0" "$?"
contains "creates a document under the hostname title" "$home/op.log" \
	"op document create $home/.ssh/config --title ssh-config-testbox --tags ssh,dotfiles"
rm -rf "$home"

echo
echo "== backup when the item exists -> edit, not a second copy"
setup
printf 'Host x\n' >"$home/.ssh/config"
run yes backup >/dev/null; check "succeeds" "0" "$?"
contains "edits the existing document" "$home/op.log" "op document edit ssh-config-testbox $home/.ssh/config"
if grep -qF "document create" "$home/op.log"; then check "does not also create" "no" "yes"; else echo "ok   does not also create"; fi
rm -rf "$home"

echo
echo "== restore -> fetch to ~/.ssh/config, mode 600"
setup
run no restore >/dev/null; check "succeeds" "0" "$?"
check "wrote the file" "RESTORED" "$(cat "$home/.ssh/config" 2>/dev/null)"
check "mode is 600" "600" "$(stat -c '%a' "$home/.ssh/config" 2>/dev/null || stat -f '%Lp' "$home/.ssh/config")"
contains "fetched by the hostname title" "$home/op.log" \
	"op document get ssh-config-testbox --out-file $home/.ssh/config"
rm -rf "$home"

echo
echo "== an unknown subcommand is a usage error"
setup
run no frobnicate >/dev/null 2>&1; check "exits 2" "2" "$?"
rm -rf "$home"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
