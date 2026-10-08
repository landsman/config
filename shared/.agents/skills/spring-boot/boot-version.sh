#!/usr/bin/env bash
# Print the Spring Boot version a project builds with, read from its build files
# without running the build: `<version><TAB><file>` per declaration, exit 1 when
# there is none. Maven (parent or imported BOM, `${property}` resolved) and Gradle
# (plugin, BOM or legacy classpath, in Groovy, Kotlin DSL, a version catalog or
# gradle.properties).
#
#   boot-version.sh [project-dir]
#
# ponytail: reads declarations, not the resolved model — a version inherited from
# a parent outside the repo, or set by a convention plugin, is not seen. The
# build tool is the authority then: ./mvnw help:effective-pom, ./gradlew buildEnvironment.
set -eu

dir=${1:-.}
cd "$dir"

files() { # files <name pattern>... — tracked files when in git, else a find without build output
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		local p
		# -co: a file not committed yet counts too, an ignored one does not
		for p in "$@"; do git ls-files -co --exclude-standard -- "$p" "**/$p"; done
	else
		local args=() p
		for p in "$@"; do args+=(-o -name "$p"); done
		find . \( -name target -o -name build -o -name node_modules -o -name .gradle \) -prune \
			-o -type f \( "${args[@]:1}" \) -print | sed 's#^\./##'
	fi | sort -u
}

# A property's value, looked up the way each build tool spells it.
pom_prop() { files pom.xml | xargs -r cat | tr -d '\n' | grep -oE "<$1>[^<]+</$1>" | head -1 | sed -E 's/<[^>]+>//g'; }
gradle_prop() { files gradle.properties | xargs -r grep -hE "^[[:space:]]*$1[[:space:]]*[=:]" | head -1 | sed -E 's/^[^=:]*[=:][[:space:]]*//'; }
catalog_ref() { files '*.versions.toml' | xargs -r grep -hE "^[[:space:]]*\"?$1\"?[[:space:]]*=" | head -1 | sed -E 's/^[^=]*=[[:space:]]*"([^"]+)".*/\1/'; }

found=0
emit() { # emit <version or ${ref}> <file> <resolver>
	local v=$1
	case $v in
	\$\{*\}) v=$("$3" "${v:2:${#v}-3}") ;;
	\$*) v=$("$3" "${v:1}") ;;
	esac
	[ -n "$v" ] || return 0
	printf '%s\t%s\n' "$v" "$2"
	found=1
}

for f in $(files pom.xml); do
	# One line, because the version sits on its own line after the artifactId.
	for v in $(tr -d '\n' <"$f" | grep -oE '<artifactId>spring-boot-(starter-parent|dependencies)</artifactId>[[:space:]]*(<(groupId|type|scope|relativePath)>[^<]*</[a-zA-Z]+>[[:space:]]*)*<version>[^<]+</version>' |
		sed -E 's/.*<version>([^<]+)<\/version>/\1/'); do
		emit "$v" "$f" pom_prop
	done
done

for f in $(files 'build.gradle' 'build.gradle.kts' 'settings.gradle' 'settings.gradle.kts'); do
	# id("org.springframework.boot") version "3.5.6", or a version held in a variable
	for v in $(grep -oE "org\.springframework\.boot['\"]\)?[[:space:]]+version[[:space:]]+[^[:space:])]+" "$f" |
		sed -E 's/.*version[[:space:]]+//' | tr -d "\"'\${}"); do
		case $v in [0-9]*) emit "$v" "$f" gradle_prop ;; *) emit "\$$v" "$f" gradle_prop ;; esac
	done
	# org.springframework.boot:spring-boot-dependencies:3.5.6 — a BOM or the legacy plugin classpath
	for v in $(grep -oE "org\.springframework\.boot:spring-boot-[a-z-]+:[^'\")]+" "$f" | sed -E 's/.*://'); do
		emit "$v" "$f" gradle_prop
	done
done

for f in $(files '*.versions.toml'); do
	for line in $(grep -E 'org\.springframework\.boot' "$f" | tr -d ' '); do
		case $line in
		*version.ref=\"*) ref=${line#*version.ref=\"}; emit "\$${ref%%\"*}" "$f" catalog_ref ;;
		*version=\"*) v=${line#*version=\"}; emit "${v%%\"*}" "$f" catalog_ref ;;
		*:spring-boot-*:*) v=${line##*:}; emit "${v%%\"*}" "$f" catalog_ref ;;
		esac
	done
done

[ "$found" = 1 ] || { echo "no Spring Boot version declared under $dir" >&2; exit 1; }
