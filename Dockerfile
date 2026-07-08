FROM php:8.3-fpm-alpine AS builder
WORKDIR /app

RUN apk add --no-cache \
    zip \
    unzip \
    git \
    curl \
    nodejs \
    npm

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY . .

RUN composer dump-autoload --optimize --no-dev && \
    npm run build

RUN php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache

FROM php:8.3-fpm-alpine AS runner
WORKDIR /app

RUN apk add --no-cache \
    nginx \
    supervisor && \
    addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

COPY --from=builder /app /app

RUN chown -R appuser:appuser /app/storage /app/bootstrap/cache && \
    mkdir -p /var/log/supervisor /run/nginx && \
    chown -R appuser:appuser /var/log/supervisor /run/nginx /var/lib/nginx /var/log/nginx

RUN printf 'user appuser;\nworker_processes auto;\npid /run/nginx/nginx.pid;\nerror_log /var/log/nginx/error.log warn;\n\nevents {\n    worker_connections 1024;\n}\n\nhttp {\n    include /etc/nginx/mime.types;\n    default_type application/octet-stream;\n    access_log /var/log/nginx/access.log;\n    sendfile on;\n    keepalive_timeout 65;\n\n    server {\n        listen 8000;\n        server_name _;\n        root /app/public;\n        index index.php;\n\n        location / {\n            try_files $uri $uri/ /index.php?$query_string;\n        }\n\n        location ~ \\.php$ {\n            fastcgi_pass 127.0.0.1:9000;\n            fastcgi_index index.php;\n            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n            include fastcgi_params;\n        }\n\n        location ~ /\\.(?!well-known).* {\n            deny all;\n        }\n    }\n}\n' > /etc/nginx/nginx.conf

RUN printf '[supervisord]\nnodaemon=true\nuser=appuser\nlogfile=/var/log/supervisor/supervisord.log\npidfile=/run/supervisord.pid\n\n[program:php-fpm]\ncommand=php-fpm --nodaemonize\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0\n\n[program:nginx]\ncommand=nginx -g '\''daemon off;'\''\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0\n' > /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8000
USER appuser

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]