FROM composer:1.9

LABEL version="1.0.0"
LABEL repository="https://github.com/php-actions/behat"
LABEL homepage="https://github.com/php-actions/behat"
LABEL maintainer="Greg Bowler <greg.bowler@g105b.com>"

RUN composer global require --no-progress --dev behat/behat ^8.0
COPY entrypoint /usr/local/bin/entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint"]