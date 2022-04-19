#!/usr/bin/env bash
set -euo pipefail

# This is due to an upstream issue with RHEL7/CentOS 7 comptability with node-argon2
# See: https://github.com/cdr/code-server/pull/3422#pullrequestreview-677765057
export npm_config_build_from_source=true

main() {
  cd "$(dirname "${0}")/../.."

  source ./ci/lib.sh

  rsync "$RELEASE_PATH/" "$RELEASE_PATH-standalone"
  RELEASE_PATH+=-standalone

  # We cannot find the path to node from $PATH because yarn shims a script to ensure
  # we use the same version it's using so we instead run a script with yarn that
  # will print the path to node.
  local node_path
  node_path="$(yarn -s node <<< 'console.info(process.execPath)')"

  mkdir -p "$RELEASE_PATH/bin"
  mkdir -p "$RELEASE_PATH/lib"
  rsync ./ci/build/code-server.sh "$RELEASE_PATH/bin/code-server"
  rsync "$node_path" "$RELEASE_PATH/lib/node"

  ln -s "./bin/code-server" "$RELEASE_PATH/code-server"
  ln -s "./lib/node" "$RELEASE_PATH/node"

  cd "$RELEASE_PATH"
  yarn --production --frozen-lockfile

  create_shrinkwraps
}

create_production_shrinkwrap() {
  npm shrinkwrap

  # HACK@edvincent: The shrinkwrap file will contain the devDependencies, which by default
  # are installed if present in a lockfile. To avoid every user having to specify --production
  # to skip them, we carefully remove them from the shrinkwrap file.
  json -f npm-shrinkwrap.json -I -e "Object.keys(this.dependencies).forEach(dependency => { if (this.dependencies[dependency].dev) { delete this.dependencies[dependency] } } )"

  # HACK@edvincent: We create the shrinkwrap file from the installed node_modules folder.
  # Installing node-addon-api also creates an auto-generated folder under @parcel/node-addon-api for gyp,
  # but this actually does not have a package.json (nor it's a package that can be fetched from the repository).
  # Thus `npm shrinkwrap` doesn't know how to generate a lock entry for it, and leaves it empty - which then
  # breaks any subsequent install. We manually remove it, as on every install it will be auto-generated.
  json -f npm-shrinkwrap.json -I -e "if (this.dependencies['@parcel/node-addon-api'] == {}) { delete this.dependencies['@parcel/node-addon-api'] }"
}

create_shrinkwraps() {
  # yarn.lock or package-lock.json files (used to ensure deterministic versions of dependencies) are
  # not packaged when publishing to the NPM registry.
  # To ensure deterministic dependency versions (even when code-server is installed with NPM), we create
  # an npm-shrinkwrap.json file from the currently installed node_modules. This ensures the versions used
  # from development (that the yarn.lock guarantees) are also the ones installed by end-users

  # We first generate the shrinkwrap file for code-server itself - from being in $RELEASE_PATH
  create_production_shrinkwrap

  # Then the shrinkwrap files for the bundled VSCode
  # We don't need to remove the devDependencies for these because we control how it's installed - and
  # as such we can force the --production flag
  cd lib/vscode/
  create_production_shrinkwrap

  cd extensions/
  create_production_shrinkwrap

  cd ../../
}

main "$@"
