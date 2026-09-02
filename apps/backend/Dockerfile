FROM nginx:1.27-alpine

COPY index.html /usr/share/nginx/html/index.html

RUN sed -i 's/listen\s*80;/listen 8080;/' /etc/nginx/conf.d/default.conf

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q -O - http://localhost:8080/ || exit 1
