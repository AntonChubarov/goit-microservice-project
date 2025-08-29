# CI/CD on AWS: Terraform · Jenkins · Argo CD · EKS

Spin up a full CI/CD stack (VPC, ECR, EKS, Jenkins, Argo CD) that builds & deploys a Django app.

---

## Prerequisites
- AWS account + CLI creds (`aws configure` or `AWS_PROFILE`).
- Tools in PATH: `terraform`, `kubectl`, `helm`, `docker`, `git`, `aws`.
- GitHub PAT with repo read/write to `AntonChubarov/goit-microservice-project`.

> **Security**: Treat your PAT like a password—do not commit it.

---

## Quick Start

### 1) Deploy everything
```shell
GITHUB_USERNAME=AntonChubarov GITHUB_TOKEN=<YOUR_GITHUB_PAT> ./scripts/deploy.sh
```
Outputs will include Jenkins & Argo CD URLs once LoadBalancers are ready.

### 2) Show services URLs
```shell
sh ./scripts/show_urls.sh
```
Prints Jenkins / Argo CD / Django endpoints.

### 3) Show admin credentials
```shell
sh ./scripts/show_passwords.sh
```
- Jenkins: `admin / admin123` (unless changed)
- Argo CD: `admin / <printed password>`

### 4) Configure kubectl (optional)
```shell
sh ./scripts/aws_kubeconfig.sh
```
Updates kubeconfig for the EKS cluster from Terraform outputs to access through kubectl, k9s, etc.

### 5) Check cluster state
  1. Open Grafana URL in browser;
  2. Use Grafana credentials to log in;
  3. Go to **Dashboards** section;
  4. Open any available dashboard, **Kubernetes / Compute Resources / Cluster** for example.

### 6) Destroy everything
***Unstable! Check manually after!***
```shell
sh ./scripts/destroy.sh
```
Cleans up Helm releases, ELBs, and Terraform infra.

---

## Troubleshooting (quick)
- **URL is (pending)**: wait 1–3 minutes; re-run `show_urls.sh`.
- **Argo repo error**: ensure GitHub PAT & branch/path are correct.
- **Jenkins pipeline not created**: give Jenkins a minute after first start; verify `github-token` credential exists.
