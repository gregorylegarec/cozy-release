#!/bin/sh

command=$1
shift

case "$command" in
  start ) if [[ ! $1 == --* ]]; then
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

bump_beta() {
  remote=$1
  branch=$2
  version=$3
  beta_number="1"

  beta_tag="$version-beta.$beta_number"

  while git tag --list | egrep -q "^$beta_tag$"
  do
      beta_number=`expr $beta_number + 1`
      beta_tag="$version-beta.$beta_number"
  done

  echo "☁️ cozy-release: Tagging $beta_tag"
  git checkout $branch
  git tag $beta_tag
  if [ ! $NO_PUSH ]; then
    git push $remote $beta_tag
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

start() {
  remote=$1
  if [ ! $NO_PUSH ]; then
    warn_about_start $remote
  fi

  echo "☁️ cozy-release: Fetching $remote"
  git fetch $remote

  existing_release_branch=`git branch | grep ' release-'`
  if [[ ! -z "${existing_release_branch// }" ]]; then
    release_branch=`git branch | grep ' release-' | sed -e 's/\*//' |  sed -e 's/^[[:space:]]*//'`
    echo "❌ cozy-release: A release branch ($release_branch) already exists on $remote. End the previous release or delete $release_branch before starting a new release."
    exit 1
  fi

  echo "☁️ cozy-release: Checking out master branch"
  git checkout master && git pull

  read_current_version
  echo "☁️ cozy-release: Releasing version $current_version"

  release_branch=release-$current_version
  git branch -D $release_branch
  git checkout -b $release_branch
  if [ ! $NO_PUSH ]; then
    git push $remote HEAD
  fi

  compute_next_version $current_version
  bump_version $remote master $next_version

  bump_beta $remote $release_branch $current_version
}

if [ $command = "start" ]
then
  start ${remote:-origin}
fi
