# DHI image for Rust




```
 # Check if runs as non-root
docker run --rm dockerdevrel/dhi-rust:1-debian13 whoami
docker run --rm dockerdevrel/dhi-rust:1-debian13-dev whoami
nonroot
root
```

# Count differences in available tools

```
echo "Dev tools:" && docker run --rm dockerdevrel/dhi-rust:1-debian13-dev ls /usr/local/bin/ | wc -l
echo "Runtime tools:" && docker run --rm dockerdevrel/dhi-rust:1-debian13 ls /usr/local/bin/ | wc -l
```

```
 echo "Dev tools:" && docker run --rm dockerdevrel/dhi-rust:1-debian13-dev ls /usr/local/bin/ | wc -l
echo "Runtime tools:" && docker run --rm dockerdevrel/dhi-rust:1-debian13 ls /usr/local/bin/ | wc -l
Dev tools:
      11
Runtime tools:
      11
```


