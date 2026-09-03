FROM nginx:1.27-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

COPY default.conf.template /etc/nginx/templates/default.conf.template

ENV BACKEND_HOST=backend.internal.invalid
ENV BACKEND_PORT=80

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q -O - http://localhost:80/healthz || exit 1
