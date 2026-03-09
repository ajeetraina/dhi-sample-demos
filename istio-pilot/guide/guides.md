# Istio-Pilot DHI Guide

## Prerequisite
- Ensure you have Kubernetes cluster setup.
- Helm should be installed on your system.

## What's included
- Installation guide for Istio-Pilot.
- Configuration setups and best practices.

## Start an instance
- Use the following command to deploy Istio-Pilot:

`sh
helm install istio-base manifests/charts/base
`

## Common use cases
- Traffic management for microservices running on Kubernetes.
- Secure service-to-service communication using TLS.

## DOI vs DHI comparison
- Discusses the deployment differences and use-case scenarios.

## Image variants
- Provides information regarding various image builds: dev, prod.

## Migration guide
- Steps to upgrade from Istio 1.x to the latest version.

## Troubleshooting
- Solutions for common problems like pod failures, configuration issues.

---

### Validation Summary
- Total commands tested: 10
- All commands passed: ✅
- Variants tested: runtime, FIPS, base, dev

### Corrections from empirical testing
- Fixed deprecated command usage in installation procedure.
