#!/bin/sh

command=$1
shift

case "$command" in
  start ) if [[ ! $1 == --* ]]; then
      remote=$1; shift;
    fi ;;
  beta ) if [[ ! $1 == --* ]]; then
      remote=$1; shift;
    fi ;;
  stable ) if [[ ! $1 == --* ]]; then
      remote=$1; shift;
    fi ;;
esac

while true; do
  case "$1" in
    --no-push ) NO_PUSH=true; shift ;;
    * ) break ;;
  esac
done

read_current_version() {
  current_version=$(cat package.json | jq -rc '.version')
}

compute_next_version() {
  IFS='.' read -r -a array <<< "$1"
  major=${array[0]}
  minor=${array[1]}
  patch="0"
  next_version="$major.$(expr $minor + 1).$patch"
}

bump_version() {
  remote=$1
  branch=$2
  version=$3
  echo "☁️ cozy-release: Bumping $branch to $version"

  git checkout $branch

  jq '.version = $version' --arg version $version package.json > package.temp.json && mv package.temp.json package.json
  jq '.version = $version' --arg version $version manifest.webapp > manifest.temp.webapp && mv manifest.temp.webapp manifest.webapp

  git add package.json
  git add manifest.webapp

  git commit -m "chore: Bump version $version 🚀"

  if [ ! $NO_PUSH ]; then
    git push $remote HEAD
  fi
}

get_existing_stable_tag() {
  version=$1
  existing_stable_tag=`git tag --list | grep "^$version\$"`
}

tag_beta() {
  remote=$1
  branch=$2

  echo "☁️ cozy-release: Checking out $remote/$branch branch"
  git checkout $branch

  read_current_version

  get_existing_stable_tag $current_version
  if [[ ! -z "${existing_stable_tag// }" ]]; then
    echo "❌ cozy-release: Version $current_version has already been released as stable. You should not release new beta again. Start a new release or patch the $current_version version."
    exit 1
  fi

  beta_number="1"

  beta_tag="$current_version-beta.$beta_number"

  while git tag --list | egrep -q "^$beta_tag$"
  do
      beta_number=`expr $beta_number + 1`
      beta_tag="$current_version-beta.$beta_number"
  done

  echo "☁️ cozy-release: Tagging $beta_tag"
  git tag $beta_tag
  if [ ! $NO_PUSH ]; then
    git push $remote $beta_tag
  fi
}

tag_stable() {
  remote=$1
  branch=$2

  echo "☁️ cozy-release: Checking out $remote/$branch branch"
  git checkout $branch

  read_current_version

  get_existing_stable_tag $current_version
  if [[ ! -z "${existing_stable_tag// }" ]]; then
    echo "❌ cozy-release: Version $current_version has already been released as stable. Start a new release or patch the $current_version version."
    exit 1
  fi

  echo "☁️ cozy-release: Tagging $current_version"
  git tag $current_version

  if [ ! $NO_PUSH ]; then
    git push $remote $current_version
  fi
}

warn_about_start() {
  remote=$1
  remote_url=`git remote get-url --push $remote` || exit 1
  echo "⚠️  cozy-release start will push a new release branch to $remote ($remote_url) and will commit a version update to $remote/master."
  echo "You can change the remote repository by running 'cozy-release start <remote>'. "
  echo "To not push anything to $remote, run 'cozy-release start <remote> --no-push.'"
  read -p "Are you sure you want to continue ? (Y/n): " user_response
  if [ $user_response != "Y" ]
  then
    exit 0
  fi
}

warn_about_beta() {
  remote=$1
  remote_url=`git remote get-url --push $remote` || exit 1
  echo "⚠️  cozy-release beta will push a new beta tag to $remote ($remote_url), which will trigger continuous integration builds."
  echo "You can change the remote repository by running 'cozy-release beta <remote>'. "
  echo "To not push anything to $remote, run 'cozy-release beta <remote> --no-push.'"
  read -p "Are you sure you want to continue ? (Y/n): " user_response
  if [ $user_response != "Y" ]
  then
    exit 0
  fi
}

warn_about_stable() {
  remote=$1
  remote_url=`git remote get-url --push $remote` || exit 1
  echo "⚠️  cozy-release stable will push a new stable tag to $remote ($remote_url), which will trigger continuous integration builds, and publish a new PRODUCTION version to registry."
  echo "You can change the remote repository by running 'cozy-release stable <remote>'. "
  echo "To not push anything to $remote, run 'cozy-release stable <remote> --no-push.'"
  read -p "Are you sure you want to continue ? (Y/n): " user_response
  if [ $user_response != "Y" ]
  then
    exit 0
  fi
}

fetch_remote () {
  remote=$1
  echo "☁️ cozy-release: Fetching $remote"
  git fetch --tags $remote
}

get_existing_release_branch() {
  existing_release_branch=`git branch --all | grep "remotes/$remote/release-" | sed -e "s/  remotes\/$remote\///"`
}

start() {
  remote=$1
  if [ ! $NO_PUSH ]; then
    warn_about_start $remote
  fi

  fetch_remote $remote

  get_existing_release_branch

  if [[ ! -z "${existing_release_branch// }" ]]; then
    echo "❌ cozy-release: A release branch ($remote/$existing_release_branch) already exists. End the previous release or delete $remote/$existing_release_branch before starting a new release."
    exit 1
  fi

  echo "☁️ cozy-release: Checking out master branch"
  git checkout master && git pull

  read_current_version
  echo "☁️ cozy-release: Releasing version $current_version"

  release_branch=release-$current_version
  git checkout -b $release_branch
  if [ ! $NO_PUSH ]; then
    git push $remote HEAD
  fi

  compute_next_version $current_version
  bump_version $remote master $next_version

  tag_beta $remote $release_branch
}

beta () {
  remote=$1
  if [ ! $NO_PUSH ]; then
    warn_about_beta $remote
  fi

  fetch_remote $remote

  get_existing_release_branch
  if [[ -z ${existing_release_branch// } ]]; then
    echo "❌ cozy-release: No release branch exists on $remote. Try run 'cozy-release start' first."
    exit 1
  fi

  tag_beta $remote $existing_release_branch
}

stable () {
  remote=$1
  if [ ! $NO_PUSH ]; then
    warn_about_stable $remote
  fi

  fetch_remote $remote

  get_existing_release_branch
  if [[ -z ${existing_release_branch// } ]]; then
    echo "❌ cozy-release: No release branch exists on $remote. Try run 'cozy-release start' first."
    exit 1
  fi

  tag_stable $remote $existing_release_branch
}

case "$command" in
  start ) start ${remote:-origin} ;;
  beta ) beta ${remote:-origin} ;;
  stable ) stable ${remote:-origin} ;;
esac
