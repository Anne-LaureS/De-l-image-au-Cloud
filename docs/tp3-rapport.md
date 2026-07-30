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

### Avant durcissement (image nginx "vanilla", `server_tokens on`, sans en-têtes)

```
[à compléter avec votre sortie réelle : docker run -p 8080:80 nginx:1.27]
```

### Après durcissement (`bc/demo-web:0.1.0`)

```
[à compléter avec votre sortie réelle : curl -sI http://localhost:8080 | sort]
```

**Les six en-têtes de sécurité sont-ils tous présents ?**
`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`,
`Content-Security-Policy`, `Permissions-Policy`, `Strict-Transport-Security`
— [oui/non, à confirmer sur votre sortie].

**Le mot `nginx` apparaît-il encore ?**
Avec `server_tokens off`, l'en-tête `Server` est réduit à `nginx` sans
numéro de version (le nom du logiciel reste visible : seule la version
disparaît). [à confirmer sur votre sortie].

---

## 3. Comparaison des vulnérabilités (Trivy) — alpine vs slim

```
[à compléter : trivy image --severity HIGH,CRITICAL bc/demo-web:0.1.0]
[à compléter : trivy image --severity HIGH,CRITICAL bc/demo-web:0.1.0-slim]
```

| Base | CRITICAL | HIGH | Taille image | Commentaire |
|---|---|---|---|---|
| `nginx-unprivileged:1.27-alpine` | [ ] | [ ] | [ ] | |
| `nginx-unprivileged:1.27-bookworm` (slim) | [ ] | [ ] | [ ] | |

---

## 4. Push sur un tag immuable — lien avec tj-actions

**Manipulation** : reconstruire l'image (contenu modifié) puis tenter de
repousser sur le tag `0.1.0` déjà présent sur l'ECR configuré en
`image_tag_mutability = "IMMUTABLE"`.

```
[à compléter avec la sortie réelle du docker push refusé]
```

Le push est **rejeté** par ECR (`ImageTagAlreadyExistsException`) : un tag
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
