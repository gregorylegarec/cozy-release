#!/bin/sh

command=$1
shift

case "$command" in
  start ) remote=$1; shift ;;
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
  echo "☁️ cozy-release: Bumping $1 to $2"

  git checkout $1

  jq '.version = $version' --arg version $2 package.json > package.temp.json && mv package.temp.json package.json
  jq '.version = $version' --arg version $2 manifest.webapp > manifest.temp.webapp && mv manifest.temp.webapp manifest.webapp

  git add package.json
  git add manifest.webapp

  git commit -m "chore: Bump version $2 🚀"

  git push origin
}

bump_beta() {
  beta_number="1"

  beta_tag="$2-beta.$beta_number"

  while git tag --list | egrep -q "^$beta_tag$"
  do
      beta_number=`expr $beta_number + 1`
      beta_tag="$2-beta.$beta_number"
  done

  echo "☁️ cozy-release: Tagging $beta_tag"
  git checkout $1
  git tag $beta_tag
  git push origin $beta_tag
}

start()
{
  echo "☁️ cozy-release: Checking out master branch"
  git checkout master && git pull

  read_current_version
  echo "☁️ cozy-release: Current version is $current_version"
  echo "☁️ cozy-release: Releasing version $current_version"

  release_branch=release-$current_version
  git branch -D $release_branch
  git checkout -b $release_branch

  compute_next_version $current_version
  bump_version master $next_version

  bump_beta $release_branch $current_version
}

if [ $command = "start" ]
then
  start
fi
