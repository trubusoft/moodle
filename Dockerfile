FROM php:8.2-fpm

WORKDIR /var/www/html

RUN apt-get update && \
    apt-get install -y \
    git \
    zip \
    curl

# Postgreqsl dependency
# https://github.com/docker-library/php/issues/221#issuecomment-254153971
RUN apt-get install -y libpq-dev \
    && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
    && docker-php-ext-install pdo pdo_pgsql pgsql

# Install all required extensions
# gd
# https://hub.docker.com/_/php#:~:text=php%2Dsource%20delete-,PHP%20Core%20Extensions,-For%20example%2C%20if
RUN apt-get install -y \
		libfreetype-dev \
		libjpeg62-turbo-dev \
		libpng-dev \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
	&& docker-php-ext-install -j$(nproc) gd

# zip
# https://stackoverflow.com/a/45775922/6558550
RUN apt-get install -y libzip-dev
RUN docker-php-ext-install zip

# intl
RUN apt-get install -y libicu-dev
RUN docker-php-ext-install intl

# opcache
# https://docs.moodle.org/405/en/OPcache
RUN docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-install opcache

# soap
# https://stackoverflow.com/a/50121691/6558550
RUN apt-get install -y libxml2-dev
RUN docker-php-ext-install soap

# exif
RUN docker-php-ext-install exif

# set up cron for moodle
# https://forums.docker.com/t/cron-does-not-run-in-a-php-docker-container/103897
# https://stackoverflow.com/q/46235982/6558550
RUN apt-get install -y cron
RUN echo "* * * * * root /usr/local/bin/php /var/www/html/moodle/admin/cli/cron.php >/dev/null" >> /etc/crontab
RUN echo "0 0 * * * root echo               \"This cronjob runs daily for monitoring.        \" >> /var/log/moodle-cron.log 2>&1" >> /etc/crontab
# for debugging, see the moodle-cron.log for possible errors
#RUN echo "* * * * * root /usr/local/bin/php /var/www/html/moodle/admin/cli/cron.php >> /var/log/moodle-cron.log" >> /etc/crontab

# clean dependencies leftover
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up source code
COPY . moodle

RUN chown -R root moodle/
RUN chmod -R 755 moodle/

EXPOSE 9000

# https://stackoverflow.com/a/66280277/6558550
# - Set environment variables at /etc/environment to be used by cron
# - Run the cron service
# - Run the php-fpm
CMD bash -c "printenv > /etc/environment && cron && php-fpm"
