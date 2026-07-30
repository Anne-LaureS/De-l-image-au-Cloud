# De l'image au cloud — TP3 (Module 4 · IaC & Gestion des configurations)

> Objectif : construire une image nginx durcie, la publier sur un registre
> cloud (ECR ou ACR) et l'exécuter sur AWS (ECS Fargate) ou Azure
> (Container Apps), image référencée **par digest**, rôle/identité
> dédié(e), système de fichiers en lecture seule.

## Arborescence

```
.
├── docker/web/            # Partie A — image durcie
│   ├── Dockerfile
│   ├── default.conf       # server block nginx (en-têtes OWASP, server_tokens off, blocage /\.)
│   ├── .dockerignore
│   └── html/               # page statique servie
├── terraform/
│   ├── aws/                # Partie B+C option AWS : ECR + ECS Fargate
│   └── azure/               # Partie B+C option Azure : ACR + Container Apps
└── docs/
    └── tp3-rapport.md      # Livrable : rapport (Dockerfile commenté, curl, trivy, tj-actions, Doki)
```

## Partie A — Construire

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

Comparaison alpine vs slim : rebuild avec `FROM nginxinc/nginx-unprivileged:1.27-bookworm`
(variante debian "slim") et documenter l'écart dans `docs/tp3-rapport.md`.

## Partie B — Publier

### Option AWS

```bash
cd terraform/aws
terraform init
terraform apply

aws ecr get-login-password --region eu-west-3 \
  | docker login --username AWS --password-stdin <account_id>.dkr.ecr.eu-west-3.amazonaws.com

docker tag bc/demo-web:0.1.0 <account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web:0.1.0
docker push <account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web:0.1.0
# noter le digest renvoyé (sha256:...)
```

Test d'immutabilité : reconstruire l'image (ex. changer `index.html`), puis
repousser sur le **même tag** `0.1.0` → doit échouer
(`ImageTagAlreadyExistsException`). Voir l'explication et le lien avec
tj-actions dans `docs/tp3-rapport.md`.

### Option Azure

```bash
cd terraform/azure
terraform init
terraform apply

az acr login --name <acrName>
docker tag bc/demo-web:0.1.0 <acrName>.azurecr.io/bc/demo-web:0.1.0
docker push <acrName>.azurecr.io/bc/demo-web:0.1.0
```

## Partie C — Exécuter dans le cloud

Renseigner `image_digest` (variable Terraform, obligatoire, jamais un tag)
puis `terraform apply` à nouveau pour déployer le service ECS Fargate /
Azure Container App, ensuite vérifier l'accès HTTP public :

```bash
terraform apply -var="image_digest=<account_id>.dkr.ecr.eu-west-3.amazonaws.com/bc/demo-web@sha256:<digest>"
curl -sI http://<ip-ou-fqdn-publique>:8080
```

## Livrable

Voir [`docs/tp3-rapport.md`](docs/tp3-rapport.md) — rapport complet
(Dockerfile commenté, sorties curl avant/après, tableau comparatif
trivy, incident tj-actions, question Doki).
