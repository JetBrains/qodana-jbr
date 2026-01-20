#!/bin/bash
sourceFlavor="linux-x64"
targetFlavors=("linux-aarch64" "linux-x64" "osx-aarch64" "osx-x64" "windows-aarch64" "windows-x64")

jarsDir="./jars"
jbrsDir="./jbrs"
qodanaJbrsDir="./qodana-jbrs"
sourceFlavorDir=${jbrsDir}/${sourceFlavor}

function setup() {
  mkdir -p "$jarsDir"
  mkdir -p "$jbrsDir"
  mkdir -p "$qodanaJbrsDir"
}

function download_jbrs() {
  tagName=$(gh -R https://github.com/JetBrains/JetBrainsRuntime release view --json tagName --jq .tagName)
  version=$(echo "$tagName" | sed -n 's/jbr-release-\(.*\)b.*/\1/p')
  build=$(echo "$tagName" | sed -n 's/.*\(b.*\)/\1/p')
  echo -e "Detected latest available JBR version $version, build $build \n"

  for flavor in "${targetFlavors[@]}"; do
    curFlavorDir="${jbrsDir}/${flavor}"
    mkdir "$curFlavorDir"
    jbrArchiveName="jbrsdk-$version-$flavor-$build.tar.gz"
    echo Downloading "$jbrArchiveName"
    curl -L -# -O --output-dir "$curFlavorDir" "https://cache-redirector.jetbrains.com/intellij-jbr/${jbrArchiveName}"
    echo Unpacking "$flavor" JBR
    tar -xzf "${curFlavorDir}"/*.tar.gz -C "$curFlavorDir"
  done
}

function download_jars() {
  echo -e "\nFetching dependencies for qodana-cli"
  curl -L -# -O "https://github.com/JetBrains/qodana-cli/raw/refs/heads/main/internal/tooling/pom.xml"
  mvn -q dependency:copy-dependencies -DoutputDirectory="$jarsDir"
  # shellcheck disable=SC2012
  ls -lh ./jars | tr -s ' ' | cut -d' ' -f9,5
  echo
}

function generate_jmods_list() {
  sourceFlavorJdeps=$(find "$sourceFlavorDir" -name "jdeps" -type f | head -n 1)

  merged=''
  for file in "${jarsDir}"/*; do
    if [[ -f "$file" ]]; then
      curJdeps=$("$sourceFlavorJdeps" --list-deps --ignore-missing-deps "$file")

      if [[ "$curJdeps" == Error:* ]]; then
        echo Error detected in jdeps output for "$file":
        echo "$curJdeps"
        exit 1
      fi
      echo -e "\nDetected jmods for $(basename "$file"):"
      echo "$curJdeps"
      merged="$merged $curJdeps"
    fi
  done

  uniqueJdeps=$(echo "$merged" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/^,//;s/,$//')
  echo -e "\nCommon list of jmods to include in qodana-jbr:\n${uniqueJdeps} \n"
}

function generate_qd_jbrs() {
  sourceFlavorJlink=$(find "$sourceFlavorDir" -name "jlink")
  for directory in "${jbrsDir}"/*/*; do
    if [[ -d $directory ]]; then
      targetModulePath=$(find "$directory" -name "jmods" -type d)
      qdJbrName=qodana-$(basename "$directory")
      echo Generating "$qdJbrName"
      "$sourceFlavorJlink" \
      --module-path "$targetModulePath" \
      --compress=zip-6 \
      --add-modules "$uniqueJdeps" \
      --no-header-files \
      --no-man-pages \
      --strip-debug \
      --output "${qodanaJbrsDir}/${qdJbrName}"

      archive_name="${qodanaJbrsDir}/${qdJbrName}.tar.gz"
      tar -czf "$archive_name" -C "$qodanaJbrsDir" "$qdJbrName"
      echo -e "Created qodana-jbr archive: ${archive_name}\n"
    fi
  done
}

function cleanup() {
  rm -f pom.xml
  rm -rf "$jarsDir"
  rm -rf "$jbrsDir"
  rm -rf "$qodanaJbrsDir"
}

cleanup
setup
download_jbrs
download_jars
generate_jmods_list
generate_qd_jbrs
echo "All done"