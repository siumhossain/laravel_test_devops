FROM php:8.4-fpm-alpine

RUN apk add --no-cache \
    git curl zip unzip libpng-dev oniguruma-dev libxml2-dev \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

COPY . .

RUN composer install --optimize-autoloader --no-dev

EXPOSE 80
# CMD ["php-fpm"]

CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=80"]

