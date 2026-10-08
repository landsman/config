#!/usr/bin/env bash
# Self-check for ./boot-version.sh: one throwaway project per way a build can
# declare the Spring Boot version.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/boot-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # check <name> <expected output, or "" for exit 1>
	local out
	if out=$(bash "$script" "$tmp/$1" 2>/dev/null); then :; else out=""; fi
	if [ "$out" = "$2" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  want: $2"; echo "  got:  $out"; fails=$((fails + 1))
	fi
}
project() { mkdir -p "$tmp/$1/$(dirname "$2")"; cat >"$tmp/$1/$2"; }

project maven-parent pom.xml <<'EOF'
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.5.6</version>
    <relativePath/>
  </parent>
  <dependencies>
    <dependency><artifactId>spring-boot-starter-web</artifactId></dependency>
  </dependencies>
</project>
EOF
check maven-parent "$(printf '3.5.6\tpom.xml')"

project maven-bom pom.xml <<'EOF'
<project>
  <properties><spring-boot.version>4.0.1</spring-boot.version></properties>
  <dependencyManagement><dependencies><dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-dependencies</artifactId>
    <version>${spring-boot.version}</version>
    <type>pom</type><scope>import</scope>
  </dependency></dependencies></dependencyManagement>
</project>
EOF
check maven-bom "$(printf '4.0.1\tpom.xml')"

project gradle-groovy build.gradle <<'EOF'
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.4.2'
}
EOF
check gradle-groovy "$(printf '3.4.2\tbuild.gradle')"

project gradle-kts app/build.gradle.kts <<'EOF'
plugins {
    id("org.springframework.boot") version "4.1.0"
}
EOF
check gradle-kts "$(printf '4.1.0\tapp/build.gradle.kts')"

project gradle-property build.gradle <<'EOF'
plugins { id 'org.springframework.boot' version "${springBootVersion}" }
EOF
project gradle-property gradle.properties <<'EOF'
springBootVersion=3.3.5
EOF
check gradle-property "$(printf '3.3.5\tbuild.gradle')"

project gradle-legacy build.gradle <<'EOF'
buildscript { dependencies { classpath("org.springframework.boot:spring-boot-gradle-plugin:2.7.18") } }
EOF
check gradle-legacy "$(printf '2.7.18\tbuild.gradle')"

project gradle-catalog gradle/libs.versions.toml <<'EOF'
[versions]
spring-boot = "3.5.0"

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
EOF
project gradle-catalog build.gradle.kts <<'EOF'
plugins { alias(libs.plugins.spring.boot) }
EOF
check gradle-catalog "$(printf '3.5.0\tgradle/libs.versions.toml')"

# Build output and dependencies are not the project's own declaration.
project gradle-one-line build.gradle.kts <<'EOF'
plugins { java; id("org.springframework.boot") version "4.0.0-M3"; id("io.spring.dependency-management") version "1.1.7" }
EOF
check gradle-one-line "$(printf '4.0.0-M3\tbuild.gradle.kts')"

project ignored target/pom.xml <<'EOF'
<project><parent><artifactId>spring-boot-starter-parent</artifactId><version>9.9.9</version></parent></project>
EOF
check ignored ""

# In a git repo the tracked files are read, and .gitignore is honoured.
project git pom.xml <"$tmp/maven-parent/pom.xml"
project git out/pom.xml <"$tmp/ignored/target/pom.xml"
echo out/ >"$tmp/git/.gitignore"
git -C "$tmp/git" init -q
check git "$(printf '3.5.6\tpom.xml')"

[ "$fails" = 0 ]
