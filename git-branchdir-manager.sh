alias b='git-branchdir-manager'
alias gbm='git-branchdir-manager'
complete -F _gb_complete b
complete -F _gb_complete gbm
complete -F _gb_complete git-branchdir-manager

SOURCE=${BASH_SOURCE[0]}
while readlink $SOURCE; do
    SOURCE=$(readlink $SOURCE)
done
export GB_VERSION=$(cat ${SOURCE/git-branchdir-manager.sh/VERSION} 2> /dev/null || echo 0)
export GB_GIT_NEW_WORKDIR="$(cd -P "${SOURCE/git-branchdir-manager.sh/}" && pwd)/git-new-workdir"

function _gb_env {
    [ -z "$GB_BASE_DIR" ]        && GB_BASE_DIR="$HOME/gbm"
    [ -z "$GB_DEV_BRANCH" ]      && GB_DEV_BRANCH="master"
    [ -z "$GB_DEV_REMOTE" ]      && GB_DEV_REMOTE="origin"
    [ -z "$GB_MASTER_DIR_NAME" ] && GB_MASTER_DIR_NAME=".gb_master"
    [ -z "$GB_MASTER_BRANCH" ]   && GB_MASTER_BRANCH="gb_master"
    [ -z "$GB_DEV_REMOTE_REF" ]  && GB_DEV_REMOTE_REF="$GB_DEV_REMOTE/$GB_DEV_BRANCH"
    [ -z "$GB_WORKFLOW" ]        && GB_WORKFLOW="rebase"
}

function _gb_help {
    echo "Usage:"
    echo "  gbm <repo_name> init <repo_url>"
    echo "  gbm <repo_name> <branch_name>"
    echo "  gbm <repo_name> <branch_name> update"
    echo "  gbm <repo_name> <branch_name> publish"
    echo "  gbm <repo_name> <branch_name> rm"
    echo "  gbm <repo_name> <branch_name> lib"
}

function _gb_version_check {
    local remote_version=$(curl -f "https://raw.github.com/nnutter/git-branchdir-manager/master/VERSION" 2> /dev/null)
    if [ -n "$remote_version" ] && (( "$remote_version" > "$GB_VERSION" )); then
        echo "Updated git-branchdir-manager version ($remote_version) available."
    fi
}

function _gb_current_repo {
    _gb_env
    local SUBDIR="${PWD#$GB_BASE_DIR\/}" || return 255;
    local REPO="${SUBDIR/\/*/}"
    if [ -n "$REPO" ]; then
        echo "$REPO"
    else
        return 255;
    fi
}

function _gb_current_branch {
    _gb_env
    local REPO=$(_gb_current_repo) || return 255;
    local SUBDIR="${PWD#$GB_BASE_DIR\/$REPO\/}" || return 255;
    local BRANCH="${SUBDIR/\/*/}"
    if [ -n "$BRANCH" ]; then
        echo "$BRANCH"
    else
        return 255;
    fi
}

function _gb_repos {
    _gb_env
    if [ -d "$GB_BASE_DIR" ]; then
        find "$GB_BASE_DIR" -mindepth 1 -maxdepth 2 -type d -name $GB_MASTER_DIR_NAME | sed -e "s|$GB_BASE_DIR/||" -e "s|/$GB_MASTER_DIR_NAME||"
    fi
}

function _gb_repo_master_dir {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$GB_MASTER_DIR_NAME"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"
    echo "$GB_BRANCH_DIR"
}

function _gb_branches {
    _gb_env
    local GB_REPO=$1
    local GB_REPO_DIR="$GB_BASE_DIR/$GB_REPO"
    if [ -d "$GB_REPO_DIR" ]; then
        find "$GB_REPO_DIR" -mindepth 1 -maxdepth 2 -type d -name .git | sed -e "s|$GB_REPO_DIR/||" -e "s|/.git||" | grep -v "$GB_MASTER_DIR_NAME"
    fi
}

function _gb_branch_dir {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$2"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"
    echo "$GB_BRANCH_DIR"
}

function _gb_lib_path {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$2"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"
    local GB_LIB_DIR

    [ -d "$GB_BRANCH_DIR/lib" ] && GB_LIB_DIR="$GB_BRANCH_DIR/lib"
    [ -d "$GB_BRANCH_DIR/lib/perl" ] && GB_LIB_DIR="$GB_BRANCH_DIR/lib/perl"
    echo "$GB_LIB_DIR"
}

function _gb_cd_lib_dir {
    local GB_BRANCH_DIR=$1
    if [ -d "$GB_BRANCH_DIR/lib/perl/Genome" ]; then
        cd "$GB_BRANCH_DIR/lib/perl/Genome"
    else
        [ -d "$GB_BRANCH_DIR/lib" ] && cd "$GB_BRANCH_DIR/lib"
    fi
    return 0
}

function _gb_cd_branch {
    _gb_env
    GB_REPO="$1"
    GB_BRANCH="$2"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"

    if [ ! -d "$GB_BRANCH_DIR" ]; then
        echo "ERROR: Branch directory does not exist ($GB_BRANCH_DIR)."
        echo -n "Do you wish to create the branch (y/n)? "
        local response
        read response
        if [ "$response" == "y" ]; then
            _gb_start_branch "$GB_REPO" "$GB_BRANCH"
        else
            return 255
        fi
    fi

    cd "$GB_BRANCH_DIR"
    GB_BRANCH="$(_git_current_branch)"
    _gb_cd_lib_dir "$GB_BRANCH_DIR"
}

function _git_tracking_ref {
    _gb_env
    local GB_UPSTREAM_BRANCH=$(git config --get branch.$GB_BRANCH.merge | sed 's/^refs\/heads\///')
    local GB_UPSTREAM_REMOTE=$(git config --get branch.$GB_BRANCH.remote)
    if [ -z "$GB_UPSTREAM_BRANCH" ] || [ -z "$GB_UPSTREAM_REMOTE" ]; then
        return 255
    else
        echo "$GB_UPSTREAM_REMOTE/$GB_UPSTREAM_BRANCH"
    fi
}

function _gb_rm_branch {
    _gb_env

    local GB_REPO="$1"
    local GB_BRANCH="$2"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"

    if [ ! -d "$GB_BRANCH_DIR" ]; then
        echo "ERROR: Branch directory does not exist ($GB_BRANCH_DIR)."
        return 255
    fi

    PRIOR_DIR=$(pwd)
    [[ -d "$GB_BRANCH_DIR" ]] && cd "$GB_BRANCH_DIR"

    local TRACKING_REF=$(_git_tracking_ref "$GB_BRANCH")
    [[ -z "$TRACKING_REF" ]] && return 255

    local COUNT="$(git log --oneline $TRACKING_REF..HEAD | wc -l | sed 's/^ *//')"
    if [ "$COUNT" != "0" ]; then
        echo "ERROR: $COUNT unpushed commits in repo:"
        git log --oneline $TRACKING_REF..$GB_BRANCH | cat
        echo -n "Do you wish to remove this branch (y/n)? "
        local response
        read response
        if [ "$response" != "y" ]; then
            return 255;
        fi
    fi

    COUNT="$(git status -s | wc -l | sed 's/^ *//')"
    if [ "$COUNT" != "0" ]; then
        echo "ERROR: Uncommitted changes in repo:"
        git status -s
        echo -n "Do you wish to remove this branch (y/n)? "
        local response
        read response
        if [ "$response" != "y" ]; then
            return 255;
        fi
    fi

    cd "$GB_BASE_DIR/$GB_REPO/$GB_MASTER_DIR_NAME"
    echo "Removing '$GB_BRANCH_DIR'..."
    sleep 1
    rm -rf "$GB_BRANCH_DIR"
    git branch -D "$GB_BRANCH"

    if [ -d "$PRIOR_DIR" ]; then
        cd $PRIOR_DIR
    else
        if [ -d $(_gb_branch_dir "$GB_REPO" "$GB_DEV_BRANCH") ]; then
            _gb_cd_branch "$GB_REPO" "$GB_DEV_BRANCH"
        else
            cd
        fi
    fi
}

function _gb_refresh_master {
    _gb_env
    local GB_REPO="$1"

    if [ -z "$GB_REPO" ]; then
        return 255
    fi

    local ORIG_DIR="$PWD"
    local ORIG_BRANCH="$GB_BRANCH"
    local GB_MASTER_DIR="$(_gb_branch_dir "$GB_REPO" "$GB_MASTER_DIR_NAME")"
    cd "$GB_MASTER_DIR"
    if [ "$(_git_current_branch)" != "$GB_MASTER_BRANCH" ]; then
        git checkout "$GB_MASTER_BRANCH"
    fi
    git fetch -q
    git merge -q "$GB_DEV_REMOTE_REF"
    git reset -q --hard "$GB_DEV_REMOTE_REF"
    git clean -qxdf
    cd "$ORIG_DIR"
}

function _gb_start_branch {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$2"

    local GB_MASTER_DIR="$GB_BASE_DIR/$GB_REPO/$GB_MASTER_DIR_NAME"
    local GB_BRANCH_DIR="$GB_BASE_DIR/$GB_REPO/$GB_BRANCH"

    if [ ! -d "$GB_MASTER_DIR" ]; then
        echo "ERROR: git-branchdir-manager master directory does not exist ($GB_MASTER_DIR)."
        return 255
    fi

    if [ -d "$GB_BRANCH_DIR" ]; then
        echo "ERROR: Branch directory already exists ($GB_BRANCH_DIR)."
        return 255
    fi

    _gb_refresh_master "$GB_REPO" || return 255
    $GB_GIT_NEW_WORKDIR "$GB_MASTER_DIR" "$GB_BRANCH_DIR"
    cd "$GB_BRANCH_DIR"
    if _git_branch_exists "$GB_BRANCH"; then
        git checkout -q "$GB_BRANCH"
        local TRACKING_REF=$(_git_tracking_ref "$GB_BRANCH")
        if [ -n "$TRACKING_REF" ] && [ "$TRACKING_REF" != "$GB_DEV_REMOTE/$GB_DEV_BRANCH" ]; then
            echo -n "Would you like to track the remote $GB_BRANCH branch (y/n)? "
            local response
            read response
            if [ "$response" == "y" ]; then
                git reset --hard "$TRACKING_REF"
            else
                git branch --set-upstream "$GB_BRANCH" "$GB_DEV_REMOTE_REF"
                git $GB_WORKFLOW "$GB_DEV_REMOTE_REF"
            fi
        fi
    else
        git checkout -q -b "$GB_BRANCH" -t "$GB_DEV_REMOTE_REF"
    fi

    _gb_cd_lib_dir "$GB_BRANCH_DIR"
}

function _gb_update_branch {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$2"

    _gb_cd_branch "$GB_REPO" "$GB_BRANCH"

    local TRACKING_REF=$(_git_tracking_ref "$GB_BRANCH")
    [[ -z "$TRACKING_REF" ]] && return 255

    echo "Fetching..."
    git fetch -q || return 255
    git $GB_WORKFLOW "$TRACKING_REF" || return 255
}

function _gb_publish_branch {
    _gb_env
    local GB_REPO="$1"
    local GB_BRANCH="$2"

    _gb_update_branch "$GB_REPO" "$GB_BRANCH"

    _gb_refresh_master "$GB_REPO" || return 255
    git checkout -q "$GB_MASTER_BRANCH" || return 255
    git merge -q --no-ff "$GB_BRANCH" || return 255
    git push -q origin $GB_MASTER_BRANCH:$GB_DEV_BRANCH || return 255

    git checkout -q "$GB_BRANCH" || return 255
    git merge -q "$GB_MASTER_BRANCH" || return 255
}

function _gb_init_repo {
    _gb_env
    local GB_REPO="$1"
    local GB_REPO_URL="$2"
    local GB_REPO_BASE_DIR="$GB_BASE_DIR/$GB_REPO"
    local GB_REPO_MASTER_DIR="$GB_REPO_BASE_DIR/$GB_MASTER_DIR_NAME"

    if [ -z "$GB_REPO_URL" ]; then
        _gb_help
        return 255
    fi

    if [ -d "$GB_REPO_MASTER_DIR" ]; then
        echo "ERROR: Repo master dir already exists ($GB_REPO_MASTER_DIR)."
        return 255
    fi

    mkdir -p "$GB_REPO_BASE_DIR"
    if echo $GB_REPO_URL | grep -qP "^/"; then
        cp -a "$GB_REPO_URL" "$GB_REPO_MASTER_DIR"
        cd "$GB_REPO_MASTER_DIR"
        local CURRENT_BRANCH=$(_git_current_branch)
        $GB_GIT_NEW_WORKDIR "$GB_REPO_MASTER_DIR" "$GB_REPO_BASE_DIR/$CURRENT_BRANCH"
        rsync -a --delete --exclude '.git' "$GB_REPO_MASTER_DIR/" "$GB_REPO_BASE_DIR/$CURRENT_BRANCH/"
        echo "Remove '$GB_REPO_URL' after you have verified nothing is missing."
    else
        git clone -q "$GB_REPO_URL" "$GB_REPO_MASTER_DIR"
    fi
    cd "$GB_REPO_MASTER_DIR"
    git checkout -q -b "$GB_MASTER_BRANCH"
    if echo $GB_REPO_URL | grep -qP "^/"; then
        _gb_cd_branch "$GB_REPO" "$CURRENT_BRANCH"
    else
        _gb_start_branch "$GB_REPO" "master"
    fi
}

function _gb_complete {
    COMPREPLY=()
    if (( ${#COMP_WORDS[@]} == 2 )); then
        local cur=${COMP_WORDS[COMP_CWORD]}
        COMPREPLY=($(compgen -W "$(_gb_repos)" -- $cur))
    fi
    if (( ${#COMP_WORDS[@]} == 3 )); then
        local cur=${COMP_WORDS[COMP_CWORD]}
        local GB_REPO=${COMP_WORDS[1]}
        if [ -d "$(_gb_repo_master_dir "$GB_REPO")" ]; then
            COMPREPLY=($(compgen -W "$(_gb_branches $GB_REPO)" -- $cur))
        else
            COMPREPLY=($(compgen -W "init" -- $cur))
        fi
    fi
    if (( ${#COMP_WORDS[@]} == 4 )); then
        local cur=${COMP_WORDS[COMP_CWORD]}
        local GB_REPO=${COMP_WORDS[1]}
        local GB_BRANCH=${COMP_WORDS[2]}
        if [ -d "$(_gb_branch_dir "$GB_REPO" "$GB_BRANCH")" ]; then
            COMPREPLY=($(compgen -W "publish lib rm update" -- $cur))
        fi
    fi
}

function git-branchdir-manager {
    _gb_env
    _gb_version_check
    GB_REPO="$1"
    local GB_ACTION
    case $# in
        0)
            GB_ACTION="help"
            ;;
        1)
            if [ "$GB_REPO" == "update" ] || [ "$GB_REPO" == "rm" ] || [ "$GB_REPO" == "publish" ]; then
                GB_ACTION="$GB_REPO"
                GB_REPO=$(_gb_current_repo)
                if [ -z "$GB_REPO" ]; then
                    echo "ERROR: Could not determine current repo."
                    return 255;
                fi

                GB_BRANCH=$(_gb_current_branch)
                if [ -z "$GB_BRANCH" ]; then
                    echo "ERROR: Could not determine current branchdir."
                    return 255;
                fi

                local GIT_BRANCH=$(_git_current_branch)
                if [ "$GB_BRANCH" != "$GIT_BRANCH" ]; then
                    echo "ERROR: Git branch does not match branchdir."
                    return 255;
                fi
            else
                GB_ACTION="ls"
            fi
            ;;
        2)
            GB_BRANCH="$2"
            GB_ACTION="cd"
            ;;
        3)
            GB_BRANCH="$2"
            GB_ACTION="$3"
            ;;
        *)
            echo "ERROR: Too many arguments specified."
            return 255
            ;;
    esac

    if [ "$GB_BRANCH" == "init" ]; then
        GB_BRANCH="$3"
        GB_ACTION="init"
    fi

    if [ "$GB_BRANCH" == "start" ] || [ "$GB_BRANCH" == "init" ] || [ "$GB_BRANCH" == "lib" ]; then
        echo "ERROR: No branch argument specified."
        return 255
    fi

    for item in $*; do
        if [ "$item" == "--help" ] || [ "$item" == "-h" ]; then
            GB_ACTION="help"
            GB_REPO=$(_gb_current_repo)
        fi
    done

    case $GB_ACTION in
        help)
            _gb_help
        ;;
        ls)
            _gb_branches "$GB_REPO"
        ;;
        cd)
            if ! _gb_cd_branch "$GB_REPO" "$GB_BRANCH"; then
                echo "ERROR: Failed to cd to branch."
                return 255
            fi
        ;;
        rm)
            if ! _gb_rm_branch "$GB_REPO" "$GB_BRANCH"; then
                echo "ERROR: Failed to remove branch."
                return 255
            fi
        ;;
        start)
            if ! _gb_start_branch "$GB_REPO" "$GB_BRANCH"; then
                echo "ERROR: Failed to start branch."
                return 255
            fi
        ;;
        update)
            if ! _gb_update_branch "$GB_REPO" "$GB_BRANCH"; then
                echo "ERROR: Failed to update branch."
                return 255
            fi
        ;;
        publish)
            if ! _gb_publish_branch "$GB_REPO" "$GB_BRANCH"; then
                echo "ERROR: Failed to publish branch."
                return 255
            fi
        ;;
        init)
            local GB_REPO_URL="$GB_BRANCH"
            if ! _gb_init_repo "$GB_REPO" "$GB_REPO_URL"; then
                echo "ERROR: Failed to init repo."
                return 255
            fi
        ;;
        lib)
            _gb_lib_path "$GB_REPO" "$GB_BRANCH"
        ;;
        *)
            echo "ERROR: Unrecognized action ($GB_ACTION)."
        ;;
    esac
}

function git-track {
    local TRACK_BRANCH="$1"
    local CURRENT_BRANCH=$(_git_current_branch)
    echo -n "Are you sure you wish to replace the current working directory with $TRACK_BRANCH's (y/n)? "
    local response
    read response
    if [ "$response" == "y" ]; then
        git branch --set-upstream "$CURRENT_BRANCH" "$TRACK_BRANCH"
        git reset --hard "$TRACK_BRANCH"
    fi
}

function _git_current_branch {
    git branch | grep ^\* | sed 's/^\* //'
}

function _git_branch_exists {
    git show-ref --quiet "$1"
}

function _git_has_changes {
    if git status -s | grep -q '^ M'; then
        echo "1"
    fi
}
