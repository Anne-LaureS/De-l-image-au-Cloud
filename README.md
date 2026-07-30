# 🐳 De l'image au cloud — TP3

![Terraform](https://img.shields.io/badge/Terraform-AWS-844FBA?logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-hardened-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-ECR%20%2B%20ECS%20Fargate-FF9900?logo=amazonaws&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-unprivileged-009639?logo=nginx&logoColor=white)
![Security](https://img.shields.io/badge/Security-OWASP%20headers-critical?logo=owasp&logoColor=white)
![License](https://img.shields.io/badge/license-Éducatif-lightgrey)

> 🎓 Module 4 · IaC & Gestion des configurations
>
> 🎯 **Objectif** : construire une image nginx durcie 🔒, la publier sur un
> registre cloud (Amazon ECR) et l'exécuter sur AWS (ECS Fargate) —
> image référencée **par digest** 🔗, rôles IAM dédiés 🪪, système de
> fichiers en lecture seule 📛.

---

## 📁 Arborescence

```
.
├── docker/web/            # 🅰️ Partie A — image durcie
│   ├── Dockerfile
│   ├── default.conf       # server block nginx (en-têtes OWASP, server_tokens off, blocage /\.)
│   ├── .dockerignore
│   └── html/               # page statique servie
├── terraform/
│   └──  aws/                # 🅱️🅲️ Partie B+C option AWS : ECR + ECS Fargate
└── docs/
    └── tp3-rapport.md      # 📄 Livrable : rapport (Dockerfile commenté, curl, trivy, tj-actions, Doki)
```

---

## 🅰️ Partie A — Construire

```bash
cd docker/web
docker build -t bc/demo-web:0.1.0 .

docker run -d --name demo-web \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /var/cache/nginx \
  --tmpfs /var/run \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  -p 8080:8080 \
  bc/demo-web:0.1.0

curl -sI http://localhost:8080 | sort

trivy image --severity HIGH,CRITICAL bc/demo-web:0.1.0
```

🔍 Comparaison alpine vs slim : rebuild avec `FROM nginxinc/nginx-unprivileged:1.27-bookworm`
(variante debian "slim") et documenter l'écart dans `docs/tp3-rapport.md`.

---

## 🅱️ Partie B — Publier sur ECR

```bash
cd terraform/aws
terraform init
terraform apply

aws ecr get-login-password --region eu-west-3 \
  | docker login --username AWS --password-stdin <account_id>.dkr.ecr.eu-west-3.amazonaws.com

docker tag bc/demo-web:0.1.0 <account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web:0.1.0
docker push <account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web:0.1.0
# 📝 noter le digest renvoyé (sha256:...)
```

⚠️ **Test d'immutabilité** : reconstruire l'image (ex. changer `index.html`), puis
repousser sur le **même tag** `0.1.0` → doit échouer
(`ImageTagAlreadyExistsException`). Voir l'explication et le lien avec
l'incident **tj-actions** dans `docs/tp3-rapport.md`.

---

## 🅲️ Partie C — Exécuter dans le cloud

Renseigner `image_digest` (variable Terraform, **obligatoire, jamais un tag**)
puis `terraform apply` à nouveau pour déployer le service ECS Fargate,
ensuite vérifier l'accès HTTP public :

```bash
terraform apply -var="image_digest=<account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web@sha256:<digest>"
curl -sI http://<ip-publique>:8080
```

✅ Ne pas oublier `terraform destroy` en fin de TP pour ne pas laisser
tourner l'infra.

---

## 📄 Livrable

Voir 👉 [`docs/tp3-rapport.md`](docs/tp3-rapport.md) — rapport complet :
- 🐋 Dockerfile commenté
- 🌐 sorties `curl` avant/après durcissement
- 📊 tableau comparatif Trivy (alpine vs slim)
- 🔐 incident tj-actions ↔ tags immuables
- 🦠 question de fond : non-root + rootfs read-only face à Doki