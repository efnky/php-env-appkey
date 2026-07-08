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

RUN git config --global --add safe.directory /app && \
    composer dump-autoload --optimize --no-dev && \
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

COPY --from=builder /app/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8000
USER appuser

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]