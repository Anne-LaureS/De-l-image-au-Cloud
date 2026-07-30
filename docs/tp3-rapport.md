# TP3 — De l'image au cloud

Fournisseur choisi : **AWS** (ECR + ECS Fargate)

---

## 1. Dockerfile commenté

> Le Dockerfile complet est dans [`docker/web/Dockerfile`](../docker/web/Dockerfile).
> Résumé des décisions de durcissement :

| Décision | Justification |
|---|---|
| Base `nginxinc/nginx-unprivileged:1.27-alpine` | nginx tourne nativement en uid non-root (101) et écoute sur le port 8080 (>1024) : pas de `CAP_NET_BIND_SERVICE` ni de root nécessaires pour binder le port. |
| Tag de base épinglé (`1.27-alpine`, pas `latest`) | Reproductibilité du build, réduction de la dérive supply-chain (une nouvelle version de base ne s'invite pas silencieusement). |
| Variante **alpine** | Moins de paquets système embarqués que `debian-slim` ⇒ surface d'attaque et nombre de CVE potentielles réduits (mesuré en partie 4). |
| Aucun paquet supplémentaire installé | Pas de shell utilitaire ni d'outils réseau (`curl`, `wget`) superflus disponibles pour un attaquant post-compromission. |
| `COPY --chown=nginx:nginx` | Le contenu appartient à l'utilisateur applicatif, pas à root ; compatible avec un rootfs en lecture seule au runtime. |
| `USER nginx` explicite | Défense en profondeur (même si l'image de base le fait déjà par défaut). |
| `HEALTHCHECK` applicatif (`wget` sur `/`) | Vérifie que nginx répond réellement, pas seulement que le process tourne. |
| Pas de `CMD`/`ENTRYPOINT` custom | On garde `nginx -g "daemon off;"` de l'image de base, déjà pensé pour un uid non-root. |

---

## 2. `curl -sI` — avant / après durcissement

### Avant durcissement (`nginx:1.27` vanilla, `docker run -p 8082:80 nginx:1.27`)

```
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 30 Jul 2026 20:02:32 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Wed, 16 Apr 2025 12:01:11 GMT
Connection: keep-alive
ETag: "67ff9c07-267"
Accept-Ranges: bytes
```

### Après durcissement (`anne-laure/demo-web:0.1.0`)

```
HTTP/1.1 200 OK
Server: nginx
Date: Thu, 30 Jul 2026 20:01:21 GMT
Content-Type: text/html
Content-Length: 89
Last-Modified: Thu, 30 Jul 2026 19:53:16 GMT
Connection: keep-alive
ETag: "6a6babac-59"
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer-when-downgrade
Content-Security-Policy: default-src 'self'; frame-ancestors 'none'; base-uri 'self'
Permissions-Policy: geolocation=(), microphone=(), camera=()
Strict-Transport-Security: max-age=63072000; includeSubDomains
Accept-Ranges: bytes
```

**Les six en-têtes de sécurité sont-ils tous présents ?**
Oui : `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`,
`Content-Security-Policy`, `Permissions-Policy`, `Strict-Transport-Security`
sont tous présents dans la réponse durcie, absents dans la réponse vanilla.

**Le mot `nginx` apparaît-il encore ?**
Oui, partiellement : `server_tokens off` supprime uniquement le **numéro de
version** (`nginx/1.27.5` → `nginx`). Le nom du logiciel reste visible ;
seule la version — l'information exploitable pour cibler une CVE connue —
disparaît.

---

## 3. Comparaison des vulnérabilités (Trivy) — alpine vs slim

### Résultat `anne-laure/demo-web:0.1.0` (base `nginx-unprivileged:1.27-alpine`, alpine 3.21.3)

```
Total: 34 (HIGH: 32, CRITICAL: 2)
```

Détail des paquets concernés :

| Paquet | CVE notables | Sévérité max | Version installée | Version corrigée |
|---|---|---|---|---|
| libssl3 / libcrypto3 | CVE-2026-31789 (heap overflow X.509 32-bit) | CRITICAL | 3.3.3-r0 | 3.3.7-r0 |
| libxml2 | CVE-2025-49794/95/96, CVE-2026-6732 | HIGH | 2.13.4-r6 | 2.13.9-r0/r1 |
| libpng | CVE-2025-64720/65018/66293, CVE-2026-22695/22801/25646 | HIGH | 1.6.47-r0 | 1.6.53→55-r0 |
| libexpat | CVE-2025-59375, CVE-2026-25210/45186/56131/56408 | HIGH | 2.7.0-r0 | 2.7.2→2.8.2-r0 |
| c-ares | CVE-2026-33630 (use-after-free) | HIGH | 1.34.5-r0 | 1.34.8-r0 |
| musl / musl-utils | CVE-2026-40200 (stack-based RCE) | HIGH | 1.2.5-r9 | 1.2.5-r11 |
| nghttp2-libs | CVE-2026-27135 (DoS HTTP/2) | HIGH | 1.64.0-r0 | 1.68.1 |
| zlib | CVE-2026-22184 (buffer overflow untgz) | HIGH | 1.3.1-r2 | 1.3.2-r0 |

Point notable : la quasi-totalité des CVE ont un correctif disponible
(`Fixed Version` renseigné) — la base `1.27-alpine` embarquée dans l'image
n'a simplement pas encore reçu ces derniers patchs alpine. Un `docker build
--pull` régulier (ou l'ajout d'un `RUN apk upgrade --no-cache` dans le
Dockerfile) réduirait déjà une bonne partie de ce total sans changer de
base.

### Résultat `anne-laure/demo-web:0.1.0-slim` (base `nginx-unprivileged:1.27-bookworm`, debian 12.11)

```
Total: 118 (HIGH: 106, CRITICAL: 12)
```

144 paquets scannés (contre 68 sur alpine). Les 12 CRITICAL touchent
notamment : `libaom3` (CVE-2023-6879, heap-buffer-overflow), `libgnutls30`
(CVE-2026-33845), `libxml2` (CVE-2024-56171, use-after-free), `libssl3` /
`openssl` (CVE-2026-31789, la même que sur alpine), `perl-base`
(CVE-2026-13221), `zlib1g` (CVE-2023-45853). La quasi-totalité de ces
paquets (codecs image `libaom3`/`libheif1`/`libde265`, `perl-base`,
`libgssapi-krb5`/`libldap`, `gnutls`) **n'existent tout simplement pas**
dans l'image alpine : ce sont des dépendances par défaut de l'image
`bookworm` (souvent héritées de paquets `Recommends`/`Suggests` debian),
pas des composants nécessaires à nginx.

### Tableau comparatif

| Base | CRITICAL | HIGH | Total CVE | Paquets scannés | Taille disque | Content size |
|---|---|---|---|---|---|---|
| `1.27-alpine` (alpine 3.21.3) | 2 | 32 | **34** | 68 | 73.7 MB | 21 MB |
| `1.27-bookworm` (slim, debian 12.11) | 12 | 106 | **118** | 144 | 279 MB | 72.4 MB |

**Conclusion** : la variante alpine réduit à la fois le nombre de CVE
(facteur ~3,5) **et** la taille de l'image (facteur ~3,8, que ce soit en
taille disque ou en "content size") par rapport à la variante debian/slim.
Ce n'est pas une coïncidence : moins de paquets système embarqués signifie
mécaniquement moins de code tiers exposé, donc moins de CVE possibles et
une image plus légère à télécharger/scanner/démarrer. C'est l'argument
principal en faveur du choix alpine retenu en partie A, au prix d'une base
musl moins répandue en production que glibc (à mettre en balance selon
le contexte — certaines applications compilées pour glibc ne fonctionnent
pas nativement sous musl).

---

## 4. Push sur un tag immuable — lien avec tj-actions

**Blocage rencontré (compte AWS partagé, utilisateur IAM `simonnet`)** :
la création du registre ECR (`terraform apply -target=aws_ecr_repository.demo_web`)
échoue systématiquement :

Error: creating ECR Repository (simonnet/demo-web): operation error ECR: CreateRepository,
https response error StatusCode: 400, api error AccessDeniedException:
User: arn:aws:iam::747082607185:user/simonnet is not authorized to perform:
ecr:CreateRepository on resource: arn:aws:ecr:eu-west-3:747082607185:repository/simonnet/demo-web
because no identity-based policy allows the ecr:CreateRepository action

Investigation menée pour cerner le périmètre exact du blocage (tests
successifs, sans deviner de nom de ressource au hasard) :

| Service testé | Action | Résultat |
|---|---|---|
| EC2 (VPC, subnet, Internet Gateway, route table, security group) | `Create*` | ✅ Autorisé — toute la couche réseau a été provisionnée avec succès |
| EC2 | `DescribeVpcs` | ✅ Autorisé |
| ECR | `CreateRepository`, `DescribeRepositories` | ❌ `AccessDenied` |
| IAM | `CreateRole`, `ListRoles`, `ListAttachedUserPolicies`, `ListUserPolicies` | ❌ `AccessDenied` |
| ECS | `ListClusters` | ❌ `AccessDenied` |

**Conclusion de l'investigation** : le compte AWS partagé applique un
scope de permissions précis à l'utilisateur `simonnet` — l'ensemble de la
couche réseau (EC2) est autorisé en création, mais tout ce qui touche à
l'identité (IAM) et aux conteneurs (ECR, ECS) est explicitement refusé,
indépendamment du nom donné aux ressources (testé avec plusieurs noms de
repository ECR différents, même résultat systématique). Ce n'est donc pas
un problème de nommage ou de code Terraform — le plan Terraform se génère
correctement (`terraform plan` aboutit sans erreur) et les ressources
réseau se créent sans problème ; seul l'appel réel aux API IAM/ECR/ECS est
rejeté par la politique IAM du compte.

**Ce qui a donc pu être validé** : le module Terraform réseau (VPC, subnet
public, Internet Gateway, route table, security group scopé au seul port
applicatif 8080) fonctionne de bout en bout et a été appliqué avec succès
sur le compte partagé (`vpc-07cbe47a143f25607`, `subnet-042a3317440ba6ecd`,
`sg-05fb31b00fb7b69bd`).

**Ce qui reste bloqué en attente de droits complémentaires** : création du
registre ECR, des rôles IAM d'exécution/de tâche, et du cluster ECS —
et donc l'ensemble du test d'immutabilité de tag demandé ci-dessous, qui
nécessite un push réel sur un registre existant.

---

*Le paragraphe ci-dessous documente ce qui **aurait dû** se produire lors
du test d'immutabilité, une fois le registre ECR accessible — logique
vérifiée sur la configuration Terraform (`image_tag_mutability = "IMMUTABLE"`)
mais non testée en conditions réelles faute d'accès.*

**Manipulation prévue** : reconstruire l'image (contenu modifié) puis tenter de
repousser sur le tag `0.1.0` déjà présent sur l'ECR configuré en
`image_tag_mutability = "IMMUTABLE"`.

Le push serait **rejeté** par ECR (`ImageTagAlreadyExistsException`) : un tag
donné, une fois publié, pointe définitivement vers le même digest.

**Lien avec l'incident tj-actions/changed-files (mars 2025)** : l'attaquant
avait compromis l'action GitHub `tj-actions/changed-files` en modifiant
rétroactivement le contenu pointé par des tags de versions déjà publiées
(retag), de sorte que les pipelines CI qui référençaient l'action par tag
(ex. `@v45`) récupéraient silencieusement du code malveillant sans qu'aucune
nouvelle version n'apparaisse — le code a exfiltré des secrets CI en clair
dans les logs de build. Un tag ECR **immuable** empêche exactement ce
scénario côté registre d'images : impossible de faire pointer un tag déjà
publié vers un contenu différent. C'est aussi pourquoi le déploiement
(partie C) référence l'image **par digest** et non par tag : même si un
tag mutable existait ailleurs dans la chaîne, le digest garantit que c'est
strictement l'octet-pour-octet validé qui est déployé.

---

## 5. Question de fond — utilisateur non-root & rootfs en lecture seule face à Doki

**Doki** est un malware Linux/conteneur qui cible en priorité les hôtes
Docker mal configurés (API Docker exposée sans authentification, socket
Docker monté dans un conteneur), utilise la blockchain Dogecoin pour générer
dynamiquement son domaine de commande et contrôle (évitant le blocage par
liste noire), puis cherche à persister sur l'hôte ou dans le conteneur
compromis (cron, binaires déposés sur disque, comptes/clés SSH ajoutés).

### Ce que `readonlyRootFilesystem=true` + utilisateur non-root **auraient changé**

- **Pas d'écriture de payload sur le système de fichiers du conteneur** : un
  rootfs en lecture seule empêche le malware de déposer son binaire, un
  script cron, ou de modifier les fichiers de configuration/binaires nginx
  pour persister dans le conteneur lui-même.
- **Pas d'élévation ni d'altération de fichiers appartenant à root** :
  l'utilisateur non-root ne peut pas modifier `/etc`, ajouter des utilisateurs
  système, ou remplacer des binaires système protégés par les permissions
  Unix classiques.
- **Réduction de la surface post-exploitation** : sans capacité d'écriture
  durable ni privilège root, un attaquant qui obtient l'exécution de code
  dans le conteneur ne peut pas facilement installer une persistance
  "container-side" ni pivoter via des outils qu'il aurait déposés sur disque.

### Ce que ces deux mesures **n'auraient pas empêché**

- **La compromission initiale elle-même** : si le vecteur d'entrée de Doki
  est une API Docker exposée sur l'hôte (le cas réel documenté), c'est un
  problème au niveau du **démon Docker / de l'hôte**, totalement en dehors
  du périmètre des réglages internes au conteneur applicatif. Non-root et
  rootfs read-only à l'intérieur du conteneur ne protègent pas l'hôte contre
  un accès direct au socket Docker.
- **L'exécution en mémoire** : du code malveillant qui s'exécute uniquement
  en mémoire (sans jamais écrire sur disque) n'est pas gêné par un rootfs
  en lecture seule.
- **L'exfiltration réseau et le C2** : ni le rootfs en lecture seule ni
  l'utilisateur non-root ne filtrent le trafic sortant ; Doki continuerait
  de pouvoir contacter son domaine de C2 dynamique si aucune règle réseau
  (security group, NetworkPolicy, egress filtering) ne le bloque par
  ailleurs.
- **L'évasion par vulnérabilité noyau** : le noyau est partagé avec l'hôte ;
  un exploit de type container escape via une CVE noyau n'est pas neutralisé
  par ces deux mesures (elles réduisent la probabilité de scénario "classique"
  mais pas ce type de vecteur).
- **Les volumes/tmpfs explicitement montés en écriture** : dans ce TP,
  `/tmp`, `/var/cache/nginx` et `/var/run` restent inscriptibles (nécessaire
  au fonctionnement de nginx) ; un attaquant qui obtient l'exécution de code
  peut toujours écrire dans ces emplacements temporaires, même si cela ne
  survit pas au redémarrage du conteneur.

**Conclusion** : `readonlyRootFilesystem` + utilisateur non-root sont des
mesures de **confinement post-compromission** efficaces contre la
persistance et l'altération du conteneur, mais ne remplacent ni le
filtrage réseau, ni la sécurisation du démon Docker/de l'hôte, ni le
patching du noyau — c'est une couche de défense en profondeur, pas une
protection à elle seule suffisante contre un malware comme Doki.
