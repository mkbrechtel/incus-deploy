#!/bin/bash

# fail on errors
set -e

# Check if there are git changes
if [[ $(git status --porcelain) ]]; then
    echo "Error: Working directory not clean"
    git status
    exit 1
fi

# Switch to refactoring branch and reset it to refactoring-with-script
git checkout refactoring
git reset --hard refactoring-with-script

# Define book names
books=("netplan" "environment" "nvme" "ceph" "lvmcluster" "ovn" "incus")

# Create Ansible role directories
for book in "${books[@]}"; do

    # Assert that there are no staged git files
    if [[ $(git diff --cached --name-only) ]]; then
        echo "Error: There are staged git files. Please commit or unstage them before running this script."
        exit 1
    fi

    # Create role directories
    mkdir -p "roles/${book}/tasks" "roles/${book}/vars" "roles/${book}/files" "roles/${book}/templates" "roles/${book}/defaults" "roles/${book}/meta" "roles/${book}/handlers"

    # defaults
    sed -n -e '1i---' -e '/^  vars:/,/^  [a-z]/{//!p}' "ansible/books/ceph.yaml" | sed 's/^    //g' | grep 'default(.*)' | awk  '!x[$0]++' | sed -E 's/^([a-z_]*):.*default\((.*)\).*$/\1: \2/g' | sed "s/task_/${book}_/g" > "roles/${book}/defaults/main.yaml"
    git add "roles/${book}/defaults/main.yaml"

    # vars
    sed -n -e '1i---' -e '/^  vars:/,/^  [a-z]/{//!p}' "ansible/books/ceph.yaml" | sed 's/^    //g' | grep -v 'default(.*)' | awk  '!x[$0]++' | sed "s/task_/${book}_/g" > "roles/${book}/vars/main.yaml"
    git add "roles/${book}/vars/main.yaml"

    # tasks
    sed -n -e '1i---' -e '/^  tasks:/,/^  [a-z]\|^-/{//!p}' -e 's/^- name:/#/p' "ansible/books/${book}.yaml" | sed 's/^    //g' > "roles/${book}/tasks/main.yaml"
    git add "roles/${book}/tasks/main.yaml"

    # handlers
    sed -n -e '1i---' -e '/^  handlers:/,/^-/{//!p}' "ansible/books/${book}.yaml" | sed 's/^    //g' | sed "s/task_/${book}_/g" > "roles/${book}/handlers/main.yaml"
    git add "roles/${book}/handlers/main.yaml"

    # Move files to templates if they exist
    if [ -d "ansible/files/${book}" ]; then
        mv "ansible/files/${book}"/* "roles/${book}/templates/"

        # Replace task var prefixes and remove relative path references
        sed -i -e "s/task_/${book}_/g" -e "s|../files/${book}/||g" "roles/${book}/templates"/*

        # Add templates to git
        git add "roles/${book}/templates"
    fi

    # Remove playbook
    git rm "ansible/books/${book}.yaml"

    # Commit with book-specific message
    git commit --signoff -m "Refactor the ${book} playbook (partially) to role structure"


    if [[ $(git status --porcelain) ]]; then
        echo "Error: Working directory not clean"
        git status
        exit 1
    fi

done

# Tag the refactoring with timestamp
refactoring_tag="refactoring-$(date -u +"%Y%m%d%H%M%S")"
git tag "$refactoring_tag" HEAD
git push -f origin refactoring $refactoring_tag

# switch back to refactoring-with-script branch
git checkout refactoring-with-script
