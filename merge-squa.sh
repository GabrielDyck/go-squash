#!/bin/bash

check_precondition () {
    if $(expr $1 > /dev/null); then
        echo "$2"
        exit
    fi
}

: ${1?Argument 1 "baseBranch" is not present}

LOG_DIR=~/gitsfm_logs/
mkdir -p $LOG_DIR/

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
logFileName=$LOG_DIR/merge_squash_execution$(date +%s).txt
touch $logFileName


baseBranch="$1"
commitMessage="$2"
branchName=$(git rev-parse --abbrev-ref HEAD)
branchForSquash=$branchName"_for_merge_squash";
branchPrefixRegex="[A-Z]+[0-9]*-[0-9]+.*"
prefixForCommitMessageRegex="[A-Z]+[0-9]*-[0-9]+"

isHubInstalled=0; [[ -z $(command -v hub) ]] && isHubInstalled=1

isCurlInstalled=$(command -v curl)
isJqInstalled=$(command -v jq)
prefix=""

isRegexApplied=0; [[ !  "$branchName" =~ $branchPrefixRegex ]] && isRegexApplied=1
check_precondition $isRegexApplied  "Current branch $branchName is not squasheable. Regex $branchPrefixRegex. Example: AISS-123, AISS-1234_JIRA_Title, ATP3-123_title"

if [[ $branchName =~ $prefixForCommitMessageRegex ]]; then
    prefix=$BASH_REMATCH
    commitMessage="$prefix: $commitMessage"
fi

if [[ -z "$isJqInstalled" ]]; then
        echo "You dont have installed jq. Please install it. Cannot get jiraUser from config.json"
else
    jiraUser=$(cat $scriptdir/config.json | jq -r ".jiraUser")
fi

if [ "$2" == "" ]; then
    echo "Obtaining jira summary for commit message"
    if [ "$jiraUser" == "null" ]; then
        echo "jiraUser field not configured in config.json. Cannot get jira summary"
    elif [[ -z "$isCurlInstalled" ]]; then
        echo "You dont have installed curl. Please install it. Cannot get jira summary"

    else
        n=0
        until [ $n -ge 3 ]
        do
	    echo "Enter your Jira Password"
            jiraSummary=$(curl -u $jiraUser -s "https://jira.despegar.com/rest/api/2/issue/$prefix?fields=summary" | jq -r ".fields.summary")

            if [ $? -eq 0 ]; then
            echo $jiraSummary
                if ! [ "$jiraSummary" == "null" ]; then
                    commitMessage="$prefix: $jiraSummary"
                fi
                break
            else
                echo "Cannot obtain jira summary for $prefix"
            fi
          n=$[$n+1]
       done
   fi
fi

echo Pulling repository changes
git pull

echo "Checking if $baseBranch exists in remote repository"
existBaseBrachInRemoteRepository=0; [[ -z $(git ls-remote --heads origin refs/heads/$baseBranch) ]] && existBaseBrachInRemoteRepository=1
check_precondition $existBaseBrachInRemoteRepository  "Selected branch $baseBranch doesn't exists in remote repository."


echo "Checking if $branchName exists in remote repository"


existBrachNameInRemoteRepository=0; [[ -z $(git ls-remote --heads origin refs/heads/$branchName) ]] && existBrachNameInRemoteRepository=1
check_precondition $existBrachNameInRemoteRepository  "Selected branch $branchName doesn't exists in remote repository. Push $branchName before continue. Use 'git push origin $branchName'"

check_precondition $isHubInstalled  "You dont have installed hub. Please install it"

existsUncommitedChanges=0;  [[ ! -z $(git diff origin/$branchName) ]] && existsUncommitedChanges=1
check_precondition $existsUncommitedChanges  "You have changes uncommited to your remote repository. Use 'git diff origin/$branchName' to see uncommited changes"

existsNotTrackingFiles=0;  [[ ! -z $(git status --porcelain) ]] && existsNotTrackingFiles=1
check_precondition $existsNotTrackingFiles  "You have not tracking files from local repository. Use 'git status' to see not tracking files."

echo "Pulling from $baseBranch"
git pull origin $baseBranch

existsMergeConflicts=0;  [[ ! -z $(git diff --name-only --diff-filter=U) ]] && existsMergeConflicts=1
check_precondition $existsMergeConflicts  "You have merge conflicts. Resolve it before continue with squash merge"


echo "Pushing merge prepare from $baseBranch to $branchName"
git push origin $branchName


echo "Checkout to $baseBranch"
git checkout $baseBranch

echo "Pulling from $baseBranch"
git pull origin $baseBranch

existsUncommitedChanges=0;  [[ ! -z $(git diff origin/$baseBranch) ]] && existsUncommitedChanges=1
check_precondition $existsUncommitedChanges  "You have changes uncommited to your remote repository. Use 'git diff origin/$baseBranch' to see uncommited changes"

existsNotTrackingFiles=0;  [[ ! -z $(git status --porcelain) ]] && existsNotTrackingFiles=1
check_precondition $existsNotTrackingFiles  "You have not tracking files from local repository. Use 'git status' to see not tracking files."

existsMergeConflicts=0;  [[ ! -z $(git diff --name-only --diff-filter=U) ]] && existsMergeConflicts=1
check_precondition $existsMergeConflicts  "You have merge conflicts. Resolve it before continue with squash merge"


echo Checking the non-existence of $branchForSquash
if ! [[ -z $(git branch --list $branchForSquash) ]]; then
    echo $branchForSquash exists in your local repository...
    echo "Do you want to delete $branchForSquash branch from local and remote repository?"
    echo "y : Delete and continue with the script. $branchForSquash will be regenerate with the $branchName changes."
    echo "n : Interrumpt the script. You must to resolve this conflict or generate the pull request manually."
    read -p "y/n? " -n 1 -r

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo Deleting $branchForSquash from local repository
        git branch -D $branchForSquash
        if ! [[ -z $(git ls-remote --heads origin refs/heads/$branchForSquash) ]]; then
            echo Deleting $branchForSquash from remote repository.
            $(git push origin --delete $branchForSquash)
        fi
    else
        echo Script interrumpted
        exit
    fi
fi






echo "Creating $branchForSquash"
git checkout -b $branchForSquash

echo "Squashing commits from $branchName"
git merge --squash $branchName > /dev/null

echo "Commiting squash"
git commit -S -m "$commitMessage" > /dev/null

echo "Pushing to $branchForSquash"
git push origin $branchForSquash

echo "Creating pull request"

pullRequestDescription="https://jira.despegar.com/browse/$prefix"

hub pull-request -b $baseBranch -h $branchForSquash -m "$commitMessage

$pullRequestDescription" | tee $logFileName

pullRequestUrl=$(tail -1 $logFileName| cut -d' ' -f 4)

echo Opening $pullRequestUrl in your default browser

if [ "$(uname)" == "Darwin" ]; then
    open $pullRequestUrl >/dev/null
elif [ "$(uname)" == "Linux" ]; then
    xdg-open $pullRequestUrl &>/dev/null
fi

echo "Do you want to add pullrequest url in a comment into jira issue $prefix?"
read -p "y/n? " -n 1 -r

if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo
    curl -u $jiraUser -s -X POST --data '{"body": "PR: '$pullRequestUrl'"}' -H "Content-type: application/json" https://jira.despegar.com/rest/api/2/issue/$prefix/comment > /dev/null
fi

echo "Do you want to delete $branchName branch from repository?"
read -p "y/n? " -n 1 -r

if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo
    $(git push origin --delete $branchName)
fi


exit
