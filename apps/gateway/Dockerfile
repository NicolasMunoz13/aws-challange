FROM nginx:1.27-alpine

# drop the default site, we only want our own template
RUN rm -f /etc/nginx/conf.d/default.conf

COPY default.conf.template /etc/nginx/templates/default.conf.template

# nginx's entrypoint runs envsubst on templates/*.template using whatever env vars are set below
# (only matches real env var names, so nginx's own $host/$remote_addr stay untouched)
ENV BACKEND_HOST=backend.internal.invalid
ENV BACKEND_PORT=80

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q -O - http://localhost:80/healthz || exit 1
