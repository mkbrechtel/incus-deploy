#!/bin/bash

# fail on errors
set -e

# Stage and Commit refactoring script
git add refactor.sh
git commit --signoff --amend

# Save the commit ID of the refactored version
refactoring_commit=$(git rev-parse HEAD)

git checkout HEAD ansible/

# Define book names
books=("nvme" "ceph" "lvmcluster" "ovn" "incus")

# Create Ansible role directories
for book in "${books[@]}"; do
    mkdir -p "ansible/roles/${book}/tasks" "ansible/roles/${book}/vars" "ansible/roles/${book}/files" "ansible/roles/${book}/templates" "ansible/roles/${book}/defaults" "ansible/roles/${book}/meta"
done

# Replace task var prefixes for each book
for book in "${books[@]}"; do
    sed -i "s/task_/${book}_/g" "ansible/books/${book}.yaml" "ansible/files/${book}/"*
done


# Handle default vars
for book in "${books[@]}"; do
    # Get default vars for this book
    default_vars=$(python3 -c "import yaml,sys; print('\n'.join(sorted(set(var for p in yaml.safe_load(open(sys.argv[1])) for var,val in p.get('vars', {}).items() if isinstance(val, str) and 'default(' in val))))" "ansible/books/${book}.yaml")

    # reset defaults file
    echo '---' > "ansible/roles/${book}/defaults/main.yaml"

    # Process each default var
    for var in $default_vars; do
        #echo "Processing $var for $book"
        # read the default value out of the playbook
        # the pattern `"{{ variable | default('value') }}"`.
        # just regex out the stuff inside of the brakets
        default_val=$(grep "default(" "ansible/books/${book}.yaml" | grep "${var}" | grep -o "default([^)]*)" | head -n1 | sed "s/default(//" | sed "s/)$//")
        # when it starts with [a-z] put it into an ansible template string
        if [[ "$default_val" =~ ^[a-z] ]]; then
            default_val="\"{{ $default_val }}\""
        fi
        echo $var: "$default_val" >> "ansible/roles/${book}/defaults/main.yaml"

    done
done

# Put the non default variables into the vars/main of the role
# Handle non-default vars
for book in "${books[@]}"; do
    # Get non-default vars for this book
    non_default_vars=$(python3 -c "import yaml,sys; print('\n'.join(sorted(set(var for p in yaml.safe_load(open(sys.argv[1])) for var,val in p.get('vars', {}).items() if not (isinstance(val, str) and 'default(' in val)))))" "ansible/books/${book}.yaml")

    # reset vars file
    echo '---' > "ansible/roles/${book}/vars/main.yaml"

    # For processing vars with complex values and proper indentation
    for var in $non_default_vars; do
        # Use perl to extract the complete var block with proper YAML indentation
        val=$(perl -0777 -ne '
                if (/\n    '"$var"':.*?(?=\n    \w|$|\n  \w)/s) {
                    $val = $&;  # use the entire match
                    $val =~ s/^\n    //;  # remove initial newline and spaces
                    print $val;
                }
            ' "ansible/books/${book}.yaml")

        # Only output if we found a value
        if [ ! -z "$val" ]; then
            echo "$val" >> "ansible/roles/${book}/vars/main.yaml"
        fi
    done
done

# Move files to templates
for book in "${books[@]}"; do
    # Create the templates directory if it doesn't exist
    mkdir -p "ansible/roles/${book}/templates"
    # Move all files from the book's files directory to templates
    if [ -d "ansible/files/${book}" ] && [ "$(ls -A "ansible/files/${book}")" ]; then
        mv "ansible/files/${book}"/* "ansible/roles/${book}/templates/"
    fi
done

# remove the ../files/${book}/ mentions in the files
for book in "${books[@]}"; do
    if [ -d "ansible/roles/${book}/templates" ] && [ "$(ls -A "ansible/roles/${book}/templates")" ]; then
        for file in "ansible/books/${book}.yaml" "ansible/roles/${book}/templates"/* "ansible/roles/${book}/vars/main.yaml"; do
            sed -i "s|../files/${book}/||g" "$file"
        done
    fi
done


# Replace vars section with roles section
for book in "${books[@]}"; do
    perl -i -0pe 's/\n  vars:\n((    [^\n]*|)\n)*/\n  roles:\n    - '${book}'\n/g' "ansible/books/${book}.yaml"
done

for book in "${books[@]}"; do
    # Add changed files
    git add "ansible/books/${book}.yaml" "ansible/files/${book}/" "ansible/roles/${book}/"
    # Commit with book-specific message
    git commit --signoff -m "Refactor the ${book} playbook (partially) to role structure"
done


# Tag the refactoring with timestamp
refactoring_tag="refactoring-$(date -u +"%Y%m%d%H%M%S")"
git tag "$refactoring_tag" HEAD

git push -f origin refactoring $refactoring_tag

git reset --hard $refactoring_commit
git checkout $refactoring_tag ansible
