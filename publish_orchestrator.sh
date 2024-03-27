#!/bin/bash

# Define usage function
usage() {
    echo "Usage: $0 [-v <version>] [-n <npmOrgName>] [-g <githubOrgName>] [-r <githubRefName>] [-d <dryRun>]" 1>&2
    exit 1
}

# Set default values
VERSION=""
NPM_ORG_NAME="masayag-tests"
GITHUB_ORG_NAME="masayag"
GITHUB_REF_NAME="main"
DRY_RUN="true"

# Parse options
while getopts ":v:n:g:r:d:" opt; do
    case $opt in
        v) VERSION="$OPTARG";;
        n) NPM_ORG_NAME="$OPTARG";;
        g) GITHUB_ORG_NAME="$OPTARG";;
        r) GITHUB_REF_NAME="$OPTARG";;
        d) DRY_RUN="$OPTARG";;
        *) usage;;
    esac
done

# Validate options
if [ -z "$VERSION" ]; then
    echo "Error: Version is required."
    usage
fi

# Get commit hash
COMMIT_HASH=$(git rev-parse HEAD)

# Checkout backstage-plugins
git clone --depth=1 --branch="$GITHUB_REF_NAME" "https://github.com/$GITHUB_ORG_NAME/backstage-plugins.git"

# Setup Node.js
NODE_VERSION="18.x"
curl -fsSL https://deb.nodesource.com/setup_"$NODE_VERSION" | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g yarn

# Install dependencies
cd backstage-plugins
yarn --prefer-offline --frozen-lockfile

cd plugins/orchestrator-common
current_version_common_package=$(node -p "require('./package.json').version")
cd -
echo "current_version_common_package= $current_version_common_package"

# Update package version
for folder in "plugins/orchestrator-common" "plugins/orchestrator" "plugins/orchestrator-backend"; do
    echo "Update version of $folder"
    cd "$folder"
    yarn version --new-version "$VERSION" --no-git-tag-version
    sed -i 's/"@janus-idp\/backstage-plugin-orchestrator-common": "'"$current_version_common_package"'"/"@janus-idp\/backstage-plugin-orchestrator-common": "'"$VERSION"'"/g' package.json
    git diff ./package.json
    cd -
done

# Replace the package organization name
for old_string in "@janus-idp/backstage-plugin-orchestrator" "janus-idp.backstage-plugin-orchestrator"; do
    new_string="@${NPM_ORG_NAME}/backstage-plugin-orchestrator"
    grep -rl "$old_string" | xargs sed -i "s|$old_string|$new_string|g"
done

# Print package names and versions
for folder in "plugins/orchestrator-common" "plugins/orchestrator" "plugins/orchestrator-backend"; do
    echo "Package name: $(node -p "require('./$folder/package.json').name")"
    echo "Package version: $(node -p "require('./$folder/package.json').version")"
done

# Refresh dependencies
yarn --prefer-offline --frozen-lockfile

# Build the packages
for folder in "plugins/orchestrator-common" "plugins/orchestrator" "plugins/orchestrator-backend"; do
    echo "Build $folder"
    cd "$folder"
    yarn tsc && yarn build && [[ "$folder" != "plugins/orchestrator-backend" ]] && yarn export-dynamic
    cd -
done

# Delete exports property from orchestrator-backend/dist-dynamic
cd plugins/orchestrator-backend/dist-dynamic
jq 'del(.exports)' package.json > temp.json && mv temp.json package.json
cd -

# Publish packages to npmjs.com
if [ "$DRY_RUN" != true ]; then
    echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" >> ~/.npmrc
    for folder in "plugins/orchestrator-common" "plugins/orchestrator" "plugins/orchestrator-backend" "plugins/orchestrator-backend/dist-dynamic"; do
        cd "$folder"
        npm publish --access public
        cd -
    done
fi

# Collect integrity hashes
if [ "$DRY_RUN" != true ]; then
    package="@${NPM_ORG_NAME}/backstage-plugin-orchestrator"
    integrity=$(curl -s "https://registry.npmjs.org/$package" | jq -r ".versions[\"$VERSION\"].dist.integrity")
    backstage_plugin_orchestrator=$integrity

    package="@${NPM_ORG_NAME}/backstage-plugin-orchestrator-backend-dynamic"
    integrity=$(curl -s "https://registry.npmjs.org/$package" | jq -r ".versions[\"$VERSION\"].dist.integrity")
    backstage_plugin_orchestrator_backend_dynamic=$integrity
fi

# Publish the release on GitHub
if [ "$DRY_RUN" != true ]; then
    tag="$VERSION"
    name="$VERSION"
    body="### Commit from '$GITHUB_ORG_NAME/backstage-plugins @ $GITHUB_REF_NAME'\n'$COMMIT_HASH'\n### Packages\n- @${NPM_ORG_NAME}/backstage-plugin-orchestrator ('$backstage_plugin_orchestrator')\n- @${NPM_ORG_NAME}/backstage-plugin-orchestrator-backend-dynamic ('$backstage_plugin_orchestrator_backend_dynamic')"
    curl -X POST https://api.github.com/repos/$GITHUB_ORG_NAME/backstage-plugins/releases \
        -H "Authorization: token $GITHUB_TOKEN" \
        -d "{\"tag_name\":\"$tag\",\"name\":\"$name\",\"body\":\"$body\"}"
fi
