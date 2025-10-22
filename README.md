


## Steps to verify the whitespaces trailing

```
pip install pre-commit
pre-commit run trailing-whitespace --all-files
```

## Template for raising PR


```
git commit -m "localstack: update guides" \
           -m "- Removed references to non-existent dev variants" \
           -m "- Fixed package manager claim: DHI retains pip while removing apt" \
           -m "- Corrected system utilities description: Added specific tested utilities" \
           -m "- Corrected multi-stage build examples to use standard LocalStack for setup stages" \
           -m "- Updated troubleshooting section with tested findings"
```


## Fix GPG TTY Issue

```
# Fix GPG TTY
export GPG_TTY=$(tty)

# Make it permanent (choose your shell)
echo 'export GPG_TTY=$(tty)' >> ~/.zshrc  # for zsh
# echo 'export GPG_TTY=$(tty)' >> ~/.bashrc  # for bash

# Now sign and push
git commit --amend --no-edit -S
git push origin minio-guide --force-with-lease
```

OR

```
# Step 1: Export GPG_TTY environment variable
export GPG_TTY=$(tty)

# Step 2: Now try to amend and sign the commit
git commit --amend --no-edit -S

# Step 3: Push
git push origin minio-guide --force-with-lease
```
