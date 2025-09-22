


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
