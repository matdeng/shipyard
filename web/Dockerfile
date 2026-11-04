FROM nginxinc/nginx-unprivileged:1.30-alpine
# Pull in Alpine security patches released after the base image was built (keeps Trivy green).
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://localhost:8080/nginx-health || exit 1
