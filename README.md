<img src="http://159.65.210.101/php-actions.png" align="right" alt="PHP Actions for Github" />

Run Behat tests in Github Actions.
==================================

Behat is an open source Behavior Driven Development framework. What’s behavior driven development, you ask? It's a way to develop software through a constant communication with stakeholders in form of examples; examples of how this software should help them, and you, to achieve your goals.

> Given I am on "https://github.com/php-actions/behat"
>
> When I press "Star this repository"
>
> Then I should be a stargazer of "php-actions/behat"
>
> And I should see "Unstar this repository"

Usage
-----

Create your Github Workflow configuration in `.github/workflows/ci.yml` or similar.

```yml
name: CI

on: [push]

jobs:
  build-test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - uses: php-actions/composer@v3
      - uses: php-actions/behat@v1
      # ... then your own project steps ...
```

### Version numbers

This action is released with semantic version numbers, but also tagged to the latest major release's tag always points to the latest release within the matching major version.

Please feel free to use `uses: php-actions/behat@v1` to always run the latest version of v1, or `uses: php-actions/behat@v1.0.1` to specify an exact release.

Example
-------

We've put together an extremely simple example application that uses `php-actions/behat`. Check it out here: https://github.com/php-actions/example-behat.

Inputs
------

The following configuration options are available:

+ `version` What version of Behat to use (default: latest)
+ `php_version` What version of PHP to use (default: latest)
+ `php_extensions` Space separated list of extensions to configure with the PHP build
+ `vendored_behat_path` Path to a vendored behat binary
+ `config` Configuration file location
+ `paths` Optional path(s) to exclude
+ `suite` Only execute a specific suite
+ `format` How to format tests output (pretty/progress/junit)
+ `out` Write format output to a file/directory instead of STDOUT
+ `name` Only executeCall the feature elements which match part of the given name or regex
+ `tags` Only executeCall the features or scenarios with tags matching tag filter expression
+ `role` Only executeCall the features with actor role matching a wildcard
+ `definitions` Print all available step definitions (l to list, i to show extended info, 'needle' to find specific definitions)
+ `memory_limit` Memory limit for tests
+ `args` Extra arguments to pass to the behat binary

The syntax for passing in custom input is the following: 

```yml
...
jobs:
  behat:

    ...

    - name: Behat tests
      uses: php-actions/behat@v1
      with:
        config: path/to/behat.yml
        memory_limit: 256M
```

If you require other configurations of Behat, please request them in the [GitHub issue tracker][issues].

PHP and Behat versions
----------------------

It's possible to run any version of Behaty under any version of PHP, with any PHP extensions you require. This is configured with the following inputs:

+ `version` - the version number of Behat to run, e.g. `3` or `3.11.0` (default: latest)
+ `php_version` - the version number of PHP to use, e.g. `7.4` (default: latest)
+ `php_extensions` - a space-separated list of extensions to install using [php-build][php-build], e.g. `xdebug mbstring` (default: N/A)

Please note the version number specified within your Action configuration must match your `composer.json` major version number. For example, if your composer.json requires `behat/behat 3.11.0`, you must use the version: `3.11.0` input, as major versions of PHPBehat are incompatible with each other.

If you require a specific version that is not compatible with GitHub Actions for some reason, please make a request in the [GitHub issue tracker][issues].

***

If you found this repository helpful, please consider [sponsoring the developer][sponsor].

[issues]: https://github.com/php-actions/behat/issues
[php-build]: https://github.com/php-actions/php-build
[sponsor]: https://github.com/sponsors/g105b
