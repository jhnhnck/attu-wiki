conventions for zsh scripts in this repo, derived from the existing scripts.

## file header

every script starts with exactly this:

```zsh
#!/usr/bin/env zsh
# Attu Project Wiki - <short description>
# This file is licensed under the MIT License; See LICENSE for full text.
```

complex scripts add a multi-line docblock below that with usage, caveats, and context.

for scripts that may be sourced or run inside a user's modified shell environment, add `emulate -LR zsh` after the shebang — it resets all options to zsh defaults regardless of how the caller's shell is configured.

## error handling

all scripts start with `set -eu`. additional options as needed:

| option | when to add |
|---|---|
| `-o pipefail` | any script with pipes |
| `-o noclobber` | scripts that write files with `>` |
| `-o noglob` | when glob patterns are passed as strings to remote commands or stored in variables |
| `-o nullglob` | when iterating over a glob that may match nothing |
| `-o errreturn` | when functions should propagate errors to the caller; prefer this over relying on `errexit` inside functions (see traps) |
| `-o localtraps` | inside functions that set traps |
| `-o localoptions` | inside functions that temporarily toggle options |
| `-o warncreateglobal` | during development; warns when a function creates a global variable without `typeset -g` |
| `-o warnnestedvar` | during development; warns when a function assigns to a variable from an enclosing scope |
| `-n` | ad hoc syntax check only: `zsh -n script.zsh`; never in production |
| `-x` | opt-in via `--trace` flag only; leaks secrets to stdout |

## output

use `print -P` throughout. never use `printf` or bare `echo`.

```zsh
print -P "%F{cyan}[label]%f message"   # normal step
print -P "%F{yellow}[label]%f message" # warning or skipped step
print -P "%F{red}DESTRUCTIVE:%f ..."   # dangerous action requiring confirmation
print -P "%F{green}Done.%f"            # success
print -u2 -- "error message"           # stderr (no color needed)
```

scripts that run inline (no label context) can use plain `print`:

```zsh
print "message"
```

## variables and naming

- `lower_snake_case` for all local and script-level variables
- `UPPER_SNAKE_CASE` for env vars and parsed option arrays
- quote everything: variables, paths, strings, command substitutions — `"$var"`, `"$(cmd)"`, not `$var`, `$(cmd)`

## argument parsing

use `zparseopts` for any script that accepts flags:

```zsh
typeset -a DRY_RUN_FLAG YES_FLAG
typeset -a TARGET_HOST_OPT
zparseopts -D -E -F -- \
    -dry-run=DRY_RUN_FLAG \
    -target-host:=TARGET_HOST_OPT \
    -yes=YES_FLAG

target_host="${TARGET_HOST_OPT[2]:-default}"
```

flags: `-D` removes parsed options from `$@`, `-E` allows options and positional args to be mixed, `-F` rejects unknown options (zsh 5.8+; replaces `-K`).

test boolean flags with: `(( ${#FLAG_NAME} ))` / `(( ! ${#FLAG_NAME} ))`

positional-only scripts skip `zparseopts` and just use `$1`, `$2`, etc.

## arrays

zsh arrays are **1-indexed**. `$arr[1]` is the first element.

```zsh
typeset -a arr=(one two three)   # indexed array
typeset -aU unique_arr           # indexed array with automatic deduplication
typeset -A map=(key1 val1 key2 val2)  # associative array
```

deleting an element vs clearing it:

```zsh
arr[2]=()   # removes element, shifts remaining
arr[2]=''   # sets to empty string; element still exists
```

iterating an associative array — use `"${(@kv)map}"` to preserve empty values:

```zsh
for k v in "${(@kv)map}"; do ...; done
```

checking if an array is empty:

```zsh
(( ${#arr} == 0 ))   # correct
[[ -z $arr ]]        # wrong — checks string form, not element count
```

splitting command output into an array — use `"${(@f)...}"` to split on newlines and preserve empty lines:

```zsh
lines=( "${(@f)$(cat file)}" )
```

never use `for f in $(command)` — it word-splits and glob-expands the output. capture into an array first.

glob qualifiers inline — prefer these over setting global `nullglob`:

```zsh
files=(*.sql(N))   # N = nullglob: empty array if nothing matches
dirs=(*(/)N)       # only directories, nullglob
```

**`NOMATCH` is on by default.** a glob that matches nothing aborts the script with an error. always use `(N)` for globs that may come up empty, or `setopt nullglob` at the top of scripts that iterate over file lists.

## parameter expansion

useful zsh-specific expansion flags:

| expansion | meaning |
|---|---|
| `${var:-default}` | use default if var is empty or unset |
| `${var:=default}` | assign and use default if empty or unset |
| `${var:+value}` | use value only if var is set and non-empty |
| `${+var}` | 1 if set, 0 if not — use in arithmetic: `(( ${+var} ))` |
| `${var:t}` | tail — basename of a path |
| `${var:h}` | head — dirname of a path |
| `${var:e}` | extension |
| `${var:A}` | resolve to absolute path (like `realpath`) |
| `${(P)var}` | indirect expansion — expand the variable whose name is in `$var` |
| `${(f)var}` | split value on newlines into an array |
| `${(s:x:)var}` | split value on delimiter `x` into an array |
| `${(q)var}` | shell-quote the value — safe for passing to `eval` or embedding in commands |
| `${(u)arr}` | unique elements of an array on expansion |

## section headers

```zsh
# --- Section Name -------------------------------------------------------
```

use dashes to fill to column 72. helps orient readers in long scripts.

## one-liner guards

```zsh
[[ -f "$file" ]] || { print -u2 -- "missing $file"; exit 1; }
command -v rsync >/dev/null || { print -u2 -- "missing: rsync"; exit 1; }
```

## functions

keep functions short. always use `local` or `typeset` for function-scoped variables — zsh uses dynamic scoping, so undeclared variables leak into callers:

```zsh
restore_into_volume() {
    local vol="$1" archive="$2"
    ...
}
```

`typeset` type modifiers:

```zsh
typeset -i counter=0    # integer; arithmetic without $(( ))
typeset -r CONST="val"  # read-only
typeset -g global_var   # explicit global; suppresses warncreateglobal warning
```

to return a value from a function without a subshell (avoids forking), use a nameref:

```zsh
get_value() {
    local -n _ret=$1
    _ret="result"
}
get_value myvar   # myvar now holds "result"
```

## path resolution

```zsh
script_dir="${0:A:h}"       # absolute path to the script's directory
project_dir="${script_dir:h}" # parent directory
```

## traps

```zsh
trap 'cleanup_fn' EXIT    # temp file cleanup
trap 'alert_fn' ZERR      # send alert on any command error (entry.zsh pattern)
```

always remove a trap explicitly when it's no longer needed: `trap - EXIT`

**`errexit` + traps in functions:** when a command inside a function fails under `errexit`, the `EXIT` trap does not fire before the script aborts — it is silently skipped. use `-o errreturn` on functions that do complex work so they return the error to the caller, where the trap fires normally.

## exit codes

| code | meaning |
|---|---|
| `0` | success |
| `1` | runtime error |
| `2` | usage / argument error |

## long-form options

prefer long-form options when they exist. if a short flag must be used (no long form, or it's something universally known like `tar -czf`), add an inline comment explaining it:

```zsh
# preferred
rsync --archive --hard-links --delete --info=progress2 ...
docker run --rm --user "$(id -u):$(id -g)" ...

# acceptable: no long form exists, or it is effectively universal
tar czf archive.tar.gz ...   # c=create z=gzip f=file
gzip -9 ...                  # -9 = max compression (no long form)
```

the bar for "universally known" is high. when in doubt, use long form or comment.

## comments

comments explain *why*, not what. keep them to a single terse sentence or phrase.

good:
```zsh
# --no-create-db: attu lacks CREATE privilege globally; load would fail on attu_links
```

bad:
```zsh
# dump the database
mariadb-dump ...
```

no trivial restatements of what the next line does.

## heredocs

use `<<'EOF'` (single-quoted) to suppress variable expansion inside the body. use a descriptive delimiter when it helps readability (`<<'PY'`, `<<'SQL'`):

```zsh
python3 - "$arg1" "$arg2" <<'PY'
import sys
...
PY
```

## idempotency

scripts that produce output artifacts should skip work when the artifact already exists, with an opt-out flag (`--overwrite`). use a `should_skip()` helper:

```zsh
should_skip() {
    local out="$1"
    (( ${#OVERWRITE_FLAG} )) && return 1
    if [[ -f "$out" ]]; then
        print -P "%F{yellow}skip:%f $out exists (use --overwrite to redo)"
        return 0
    fi
    return 1
}
```

## dry-run pattern

wrap destructive commands in a `run` function, set at parse time:

```zsh
if (( ${#DRY_RUN_FLAG} )); then
    run() { print -P "%F{yellow}DRY:%f $*"; }
else
    run() { "$@"; }
fi
```

## pitfalls

| pitfall | fix |
|---|---|
| `for f in $(command)` | capture into array: `files=( "${(@f)$(command)}" )` |
| `[[ -z $arr ]]` to check empty array | `(( ${#arr} == 0 ))` |
| `arr[2]=''` to remove element | `arr[2]=()` — empty string keeps the slot |
| unquoted `${(kv)map}` with empty values | `"${(@kv)map}"` — `@` preserves empty values |
| glob with no matches aborting script | add `(N)` qualifier or `setopt nullglob` |
| function variable leaking to caller | declare with `local` or `typeset` |
| `EXIT` trap not firing on function error | use `errreturn` in functions so the error propagates to the caller's `errexit` |
| `echo -e` | use `print` — `echo -e` behavior varies across shells |
| parsing `ls` output | use globs directly |

---

## metadata

```yaml
last_updated: 10 Jun 2026
```
