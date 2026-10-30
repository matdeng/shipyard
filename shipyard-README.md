# Shipyard: one project, the whole DevOps toolchain

Shipyard is a deliberately small web app wrapped in a deliberately complete delivery system. The app shows which replica answered your request, counts visits, and keeps a shared "ship log" of messages. That's enough to make load balancing, persistence, scaling, monitoring and rollouts visible, which is the whole point.

You build it in phases, and every phase uses the tools from one or more parts of the cheat sheet.

```
                       GitHub
  git push ──▶ ┌──────────────────────────────────────────────┐
               │ Actions: lint ─ test ─ terraform/k8s checks  │
               │          ─ secret scan ─ build ─ trivy scan  │
               │          ─ push images to ghcr.io            │
               └───────────────────────┬──────────────────────┘
                                       │ images
   Terraform creates                   ▼
   ┌────────────────────── AWS VPC 10.20.0.0/16 ─────────────────────────┐
   │  public subnet 10.20.1.0/24, security group: 22 + 6443 = your IP    │
   │  ┌──────────────── EC2 Ubuntu 24.04 (Ansible configures) ────────┐  │
   │  │ ufw, fail2ban, SSH keys only, auto security updates           │  │
   │  │ ┌──────────────────── k3s Kubernetes ──────────────────────┐  │  │
   │  │ │ Traefik ingress :80                                      │  │  │
   │  │ │   └▶ web (nginx) x2 ──/api/──▶ app (Flask) x2-5 ──▶ redis│  │  │
   │  │ │ monitoring: Prometheus ◀─scrapes /metrics─ app           │  │  │
   │  │ │             Grafana (grafana.<ip>.nip.io)                │  │  │
   │  │ └──────────────────────────────────────────────────────────┘  │  │
   │  └───────────────────────────────────────────────────────────────┘  │
   └─────────────────────────────────────────────────────────────────────┘
```

## What's in the repo

```
shipyard/
├── app/                  Python Flask API, tests, Dockerfile          (Python, Docker)
├── web/                  HTML frontend + nginx reverse proxy config   (Linux, nginx)
├── docker-compose.yml    whole system on your laptop                  (Docker Compose)
├── monitoring/           Prometheus config, alert rules, Grafana dashboard
├── .github/workflows/    CI/CD pipeline                               (GitHub Actions, DevSecOps)
├── terraform/            VPC, subnet, security group, EC2, Elastic IP (Terraform, AWS)
├── ansible/              harden server, install k3s, monitoring, deploy (Ansible)
├── k8s/                  Deployments, Services, Ingress, HPA, NetworkPolicy (Kubernetes)
├── scripts/              smoke test and load generator                (bash)
└── Makefile              one-word shortcuts for every phase
```

## Which cheat-sheet parts each phase practises

| Phase | You'll use |
|---|---|
| 0. Git and GitHub | Part 4 Git |
| 1. Run it locally | Part 1 Linux, Part 2 Bash, Part 3 Networking, Part 5 Python, Part 6 Docker, Part 11 Observability |
| 2. CI pipeline | Part 7 CI/CD, Part 12 Security |
| 3. Cloud infrastructure | Part 8 Cloud, Part 9 Terraform, Part 3 Networking (CIDR, security groups) |
| 4. Configure the server | Part 9 Ansible, Part 1 Linux (systemd, ufw, SSH), Part 12 Security |
| 5. Run on Kubernetes | Part 10 Kubernetes |
| 6. Watch it | Part 11 Observability |
| 7. Continuous deployment | Part 7 CI/CD |
| 8. Break it on purpose | everything |

---

## Before you start

On your laptop (Ubuntu, macOS, or Windows with WSL2), install:

- `git`, `make`, `curl`
- Docker Engine or Docker Desktop
- Python 3.12 (for running tests outside Docker)
- Terraform 1.6 or newer
- AWS CLI v2
- Ansible: `pipx install --include-deps ansible`
- kubectl

You also need a GitHub account and, from Phase 3 onwards, an AWS account.

---

## Phase 0: Put it in Git

1. On GitHub, create an empty repository named **`shipyard`**. The name matters, because image names are built from it.
2. Push the code:

   ```bash
   cd shipyard
   git init -b main
   git add .
   git commit -m "feat: initial shipyard project"
   git remote add origin git@github.com:YOUR_USER/shipyard.git
   git push -u origin main
   ```

3. In the repo settings, protect `main`: require a pull request and require the `ci` checks to pass. From now on, every change goes through a branch and a PR:

   ```bash
   git switch -c feat/my-change
   # edit, commit
   git push -u origin feat/my-change     # then open a PR on GitHub
   ```

---

## Phase 1: Run the whole system on your laptop

```bash
make test        # 7 unit tests, in-memory store, no Redis needed
make up          # docker compose up -d --build
make smoke       # checks the frontend, API through nginx, Redis, posting
```

Open these:

- App: http://localhost:8080
- Prometheus: http://localhost:9090 (try the query `rate(shipyard_http_requests_total[1m])`)
- Grafana: http://localhost:3000, log in as `admin` / `admin`, then open **Shipyard > Shipyard overview**

Now see load balancing with your own eyes:

```bash
make scale       # 3 app replicas, nginx restarted so it sees all of them
```

Click **Ask 10 times** on the page. The blocks in "the yard" turn several colours, one per replica.

Things to explore while it runs:

```bash
docker compose ps
docker compose logs -f app
docker compose exec redis redis-cli LRANGE shipyard:messages 0 -1
docker compose exec web cat /etc/nginx/conf.d/default.conf
curl -i http://localhost:8080/api/info       # note the X-Served-By header
docker stats
```

`make down` stops everything but keeps the Redis volume. `docker compose down -v` deletes the data too.

---

## Phase 2: The CI pipeline

The pipeline already ran when you pushed in Phase 0. Open the **Actions** tab to watch it. It runs these jobs:

1. **test**: ruff lint and pytest.
2. **infra-lint**: `terraform fmt` and `validate`, Kubernetes manifests checked with kubeconform, Ansible syntax check. No cloud credentials needed.
3. **secrets-scan**: gitleaks searches the whole Git history for leaked keys.
4. **build**: builds the `app` and `web` images, scans them with Trivy (fails on critical vulnerabilities), and on `main` pushes them to `ghcr.io/YOUR_USER/shipyard/app` and `/web`, tagged with the commit SHA and `latest`.
5. **deploy**: optional, see Phase 7.

After the first successful run on `main`, make the images pullable by your server. On GitHub, go to your profile > **Packages**, open `shipyard/app`, then **Package settings > Change visibility > Public**. Do the same for `shipyard/web`.

(Prefer private images? Create a GitHub token with `read:packages`, then on the server create a pull secret with `kubectl -n shipyard create secret docker-registry ghcr --docker-server=ghcr.io --docker-username=YOUR_USER --docker-password=TOKEN` and add `imagePullSecrets: [{name: ghcr}]` to both Deployments.)

Try a failing pipeline on purpose: in a branch, break a test, push, open a PR and watch it get blocked.

---

## Phase 3: Build the cloud infrastructure with Terraform

**Cost warning.** This creates a `t3.medium` server, a 30 GB disk and a public IP. In Singapore that's roughly US$1.40 per day while it exists. Prices change, so check the AWS pricing page. Always finish with `make destroy` (Phase 9) when you're done for the day or the week.

1. Give the AWS CLI credentials. Use an IAM user or IAM Identity Center, never the root account:

   ```bash
   aws configure            # or: aws configure sso
   aws sts get-caller-identity
   ```

2. Make an SSH key if you don't have one:

   ```bash
   ssh-keygen -t ed25519 -C "shipyard"
   ```

3. Fill in your variables:

   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   curl -s ifconfig.me      # put this IP into my_ip_cidr as x.x.x.x/32
   ```

4. Create everything:

   ```bash
   terraform init
   terraform plan           # read it! 10 resources to add
   terraform apply
   ```

Terraform creates the VPC, a public subnet, an internet gateway and route table, a security group (SSH and the Kubernetes API only from your IP; HTTP and HTTPS from anywhere), the EC2 instance with an encrypted disk and IMDSv2, and an Elastic IP. It also **writes `ansible/inventory.ini`**, so Ansible always targets exactly the server Terraform built.

Check it: `terraform output`, then try the `ssh` command it prints.

If your home IP changes later, update `my_ip_cidr` and run `terraform apply` again. Only the security group changes.

---

## Phase 4: Configure the server with Ansible

1. Edit `ansible/group_vars/all/main.yml` and set `github_owner` to your GitHub username in lowercase.
2. Set a real Grafana password with Ansible Vault:

   ```bash
   cd ansible
   echo 'vault_grafana_admin_password: "pick-a-long-password"' > group_vars/all/vault.yml
   ansible-vault encrypt group_vars/all/vault.yml
   ```

   From now on, add `--ask-vault-pass` when you run the playbook. (The `make` targets add it automatically once that file exists.)

3. Run everything:

   ```bash
   ansible-galaxy collection install -r requirements.yml
   ansible-playbook site.yml --ask-vault-pass
   ```

The playbook runs four roles in order:

- **common** upgrades packages, turns on automatic security updates, disables SSH passwords and root login, starts fail2ban, and sets up ufw (default deny; allow 22 rate-limited, 80, 443, 6443 and the k3s pod and service networks).
- **k3s** installs a pinned version of k3s, waits for the node to be Ready, and saves a `kubeconfig` file in the repo root that points at the server.
- **monitoring** installs Helm, then kube-prometheus-stack (Prometheus, Grafana, node-exporter, kube-state-metrics), and loads the Shipyard dashboard into Grafana.
- **deploy** copies `k8s/`, points the images at your registry, runs `kubectl apply -k`, and waits for the rollouts.

Run it a second time. Almost every task reports `ok` instead of `changed`. That's idempotence.

At the end it prints your URLs. Run the smoke test against the server:

```bash
make smoke URL=http://YOUR_IP
```

---

## Phase 5: Work with Kubernetes

```bash
export KUBECONFIG=$PWD/kubeconfig        # from the repo root
kubectl get nodes
kubectl -n shipyard get all
kubectl -n shipyard get ingress,hpa,networkpolicy,pvc
```

Try these, keeping the app open in your browser:

```bash
# scale and watch new colours appear in the yard
kubectl -n shipyard scale deploy/web --replicas=3
kubectl -n shipyard get pods -w

# logs and a shell
kubectl -n shipyard logs deploy/app -f
kubectl -n shipyard exec -it deploy/app -- sh

# the network policy in action: this is blocked (only app pods may reach Redis)
kubectl -n shipyard run probe --rm -it --image=busybox:1.36 -- nc -zv -w 3 redis 6379

# autoscaling: generate load, then watch replicas grow
scripts/load.sh http://YOUR_IP 5000 30
kubectl -n shipyard get hpa -w
```

Note that the HPA keeps the app at a minimum of 2 replicas, so `kubectl scale deploy/app` below 2 gets reverted. Scale `web` instead to experiment.

**Ship a new version.** Change something visible, for example the `<h1>` in `web/index.html`. Commit through a PR, merge, and let CI push new images. Then deploy that exact commit:

```bash
make deploy TAG=<the full commit sha>
kubectl -n shipyard rollout status deploy/web
```

The version label on the page changes to the new SHA. Rollouts use `maxUnavailable: 0`, so the page never goes down.

**Roll back:**

```bash
kubectl -n shipyard rollout history deploy/web
kubectl -n shipyard rollout undo deploy/web
```

---

## Phase 6: Watch it with Prometheus and Grafana

- Grafana: `http://grafana.YOUR_IP.nip.io`, user `admin` and your vault password. nip.io is a free DNS service where any name containing an IP resolves to that IP, so you get a hostname without buying a domain.
- Open **Dashboards > Shipyard overview** for request rate, error rate, p50 and p95 latency, requests per replica, total visits and replicas up. The **Kubernetes / Compute Resources** and **Node Exporter** dashboards come with the stack.
- Prometheus has no public URL on purpose, because it has no login. Reach it through a tunnel:

  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
  # open http://localhost:9090 > Status > Targets, and Alerts
  ```

The alert rules live in `k8s/prometheusrule.yaml`: app down, error rate over 5%, and p95 latency over 500 ms. To actually receive them, set `alertmanager.enabled: true` in `ansible/roles/monitoring/templates/monitoring-values.yaml.j2` and add a Slack or email receiver.

---

## Phase 7 (optional): Continuous deployment

The Kubernetes API is only open to your IP, so GitHub's own runners can't reach it. That's intentional. Instead, you install a **self-hosted runner** on the server. It connects out to GitHub, so nothing new has to be opened inbound.

1. In the repo, go to **Settings > Actions > Runners > New self-hosted runner > Linux**. Run the commands it shows on the server (over SSH, as the `ubuntu` user). When asked for labels, add `shipyard`. Then install it as a service with `sudo ./svc.sh install && sudo ./svc.sh start`.
2. Go to **Settings > Environments**, create `production`, and optionally require your approval.
3. Go to **Settings > Secrets and variables > Actions > Variables** and add `DEPLOY_ENABLED` = `true`.

Now every merge to `main` tests, scans, builds, pushes, then deploys the new SHA and runs a smoke test.

---

## Phase 8: Break it on purpose

This is where the real learning happens. For each one, find the cause using only the tools from the cheat sheets, then fix it.

1. **Stop Redis.** Run `kubectl -n shipyard scale deploy/redis --replicas=0`. What happens to `/ready`, the app pods' READY column and the page? Why does `/health` stay green?
2. **Ship a broken image tag.** Run `make deploy TAG=doesnotexist`. Find `ImagePullBackOff`, and notice the old pods kept serving. Roll back.
3. **Crash the app.** Set `REDIS_PORT` to `"abc"` in the ConfigMap and restart. Find `CrashLoopBackOff` and the Python error with `kubectl logs --previous`.
4. **Break nginx.** Introduce a typo in `web/nginx.conf` and run `docker compose up -d --build` locally. Which command tells you exactly which line is wrong?
5. **Close the firewall.** Remove port 80 from the security group in Terraform and apply. Is it "connection refused" or "timed out" from your laptop? Why?
6. **Fill the disk.** On the server, run `sudo fallocate -l 20G /bigfile`. Watch the node-exporter dashboard, then find the file with `du`. Delete it.
7. **Leak a fake secret.** In a branch, commit a file containing `AWS_SECRET_ACCESS_KEY=AKIA...`. Watch gitleaks stop the PR. Then work out how you'd remove it from history.
8. **Overload it.** Use `scripts/load.sh` with high parallelism. Watch latency in Grafana and replicas in the HPA. Which resource runs out first?
9. **Drift.** Change the instance's tags by hand in the AWS console, then run `terraform plan`. Run the Ansible playbook again after editing `/etc/ssh/sshd_config.d/99-shipyard.conf` by hand.

---

## Phase 9: Clean up

```bash
make destroy           # terraform destroy: removes everything Terraform made
```

Check the AWS console (EC2, Elastic IPs, VPC) to confirm nothing is left running. GitHub packages and the repo cost nothing.

---

## Stretch goals

Once all of this works, you're ready for the "real company" versions of each piece:

- Store Terraform state in S3 (see the commented backend in `terraform/versions.tf`).
- Add HTTPS with cert-manager and Let's Encrypt on a real domain.
- Replace the single node with EKS and private subnets plus a NAT gateway, using the `terraform-aws-modules/vpc` and `eks` modules.
- Move Redis to ElastiCache, and secrets to AWS Secrets Manager with External Secrets Operator.
- Replace `make deploy` with GitOps using Argo CD watching the `k8s/` folder.
- Add Loki for logs and OpenTelemetry tracing.
- Turn `k8s/` into a Helm chart with values per environment (staging and prod).

## Troubleshooting

| Symptom | Where to look |
|---|---|
| `terraform apply` fails on the key pair | `ssh_public_key_path` doesn't exist; run `ssh-keygen` |
| Ansible can't connect | `my_ip_cidr` no longer matches your IP (`curl ifconfig.me`), or the wrong key path in `inventory.ini` |
| Pods stuck in `ImagePullBackOff` | packages still private on GHCR, or `github_owner` is wrong or not lowercase |
| `servicemonitor`/`prometheusrule` "no matches for kind" | the monitoring role hasn't run; run `ansible-playbook site.yml --tags monitoring` first |
| Grafana URL doesn't load | `kubectl -n monitoring get pods,ingress`; the stack takes a few minutes on first install |
| Page loads but says "API unreachable" | `kubectl -n shipyard get pods`; check the app pods are Ready and Redis is running |
