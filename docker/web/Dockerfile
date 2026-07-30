# syntax=docker/dockerfile:1.7
#
# bc/demo-web — image nginx durcie servant une page statique
#
# Choix de durcissement (justifiés dans docs/tp3-rapport.md) :
#  1. Base "nginx-unprivileged" : nginx tourne nativement en tant qu'utilisateur
#     non-root (uid 101) et écoute sur le port 8080 (>1024), pas besoin de
#     CAP_NET_BIND_SERVICE ni de root pour binder le port.
#  2. Tag de base épinglé (pas de "latest") pour la reproductibilité et
#     limiter la dérive supply-chain.
#  3. Variante alpine choisie pour réduire la surface d'attaque (moins de
#     paquets, image plus petite -> moins de CVE potentielles) — comparée
#     à la variante "slim" (debian) dans le rapport.
#  4. Aucun paquet supplémentaire installé : pas de shell utilitaire, pas
#     de curl/wget superflu dans l'image finale.
#  5. Contenu copié avec --chown pour éviter tout accès en écriture non
#     nécessaire et rester compatible avec un système de fichiers en
#     lecture seule au runtime (--read-only + tmpfs sur les caches nginx).
#  6. USER non-root explicite (défense en profondeur, même si l'image de
#     base le fait déjà par défaut).
#  7. HEALTHCHECK applicatif plutôt que de se fier uniquement à l'état du
#     process.

FROM nginxinc/nginx-unprivileged:1.27-alpine

LABEL org.opencontainers.image.title="bc/demo-web" \
      org.opencontainers.image.description="Page statique nginx durcie - TP3 Module 4" \
      org.opencontainers.image.vendor="BC Design Systems"

# Configuration nginx durcie (en-têtes OWASP, server_tokens off, blocage /\.)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf

# Contenu statique
COPY --chown=nginx:nginx html/ /usr/share/nginx/html/

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/ >/dev/null 2>&1 || exit 1

# Pas de CMD/ENTRYPOINT custom : on garde ceux de l'image de base
# (nginx -g "daemon off;"), déjà pensés pour un uid non-root.
