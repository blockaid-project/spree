#!/usr/bin/env bash
# Used in the sandbox rake task in Rakefile

set -e

case "$DB" in
postgres)
  RAILSDB="postgresql"
  ;;
mysql)
  RAILSDB="mysql"
  ;;
sqlite|'')
  RAILSDB="sqlite3"
  ;;
*)
  echo "Invalid DB specified: $DB"
  exit 1
  ;;
esac

DB_NAME="spree_production"
DB_USER="spree"
DB_PASS="12345678"

rm -rf ./sandbox
bundle exec rails new sandbox --database="$RAILSDB" \
  --skip-bundle \
  --skip-git \
  --skip-keeps \
  --skip-rc \
  --skip-spring \
  --skip-test \
  --skip-coffee \
  --skip-javascript \
  --skip-bootsnap

if [ ! -d "sandbox" ]; then
  echo 'sandbox rails application failed'
  exit 1
fi

cd ./sandbox

if [ "$SPREE_AUTH_DEVISE_PATH" != "" ]; then
  SPREE_AUTH_DEVISE_GEM="gem 'spree_auth_devise', path: '$SPREE_AUTH_DEVISE_PATH'"
else
  SPREE_AUTH_DEVISE_GEM="gem 'spree_auth_devise', github: 'spree/spree_auth_devise', tag: 'v4.4.0'"
fi

if [ "$SPREE_GATEWAY_PATH" != "" ]; then
  SPREE_GATEWAY_GEM="gem 'spree_gateway', path: '$SPREE_GATEWAY_PATH'"
else
  SPREE_GATEWAY_GEM="gem 'spree_gateway', github: 'spree/spree_gateway', branch: 'main'"
fi

if [ "$SPREE_HEADLESS" != "" ]; then
cat <<RUBY >> Gemfile
gem 'spree', path: '..'
$SPREE_AUTH_DEVISE_GEM
$SPREE_GATEWAY_GEM
# gem 'spree_i18n', github: 'spree-contrib/spree_i18n', branch: 'main'

group :test, :development do
  gem 'bullet'
  gem 'pry-byebug'
  gem 'awesome_print'
end

# gem 'oj'
RUBY
else
cat <<RUBY >> Gemfile
gem 'spree', path: '..'
gem 'spree_frontend', path: '../frontend'
gem 'spree_backend', path: '../backend'
gem 'spree_emails', path: '../emails'
gem 'spree_sample', path: '../sample'
$SPREE_AUTH_DEVISE_GEM
$SPREE_GATEWAY_GEM
# gem 'spree_i18n', github: 'spree-contrib/spree_i18n', branch: 'main'

group :test, :development do
  gem 'bullet'
  # gem 'pry-byebug'
  gem 'awesome_print'
end

# ExecJS runtime
# gem 'mini_racer'

# temporary fix for sassc segfaults on ruby 3.0.0 on Mac OS Big Sur
# this change fixes the issue:
# https://github.com/sass/sassc-ruby/commit/04407faf6fbd400f1c9f72f752395e1dfa5865f7
gem 'sassc', github: 'sass/sassc-ruby', branch: 'master'

gem 'rack-cache'
# gem 'oj'
RUBY
fi

cat <<RUBY >> config/environments/development.rb
Rails.application.config.hosts << /.*\.lvh\.me/
RUBY

# touch config/initializers/oj.rb
# 
# cat <<RUBY >> config/initializers/oj.rb
# require 'oj'
# 
# Oj.optimize_rails
# RUBY

touch config/initializers/bullet.rb

cat <<RUBY >> config/initializers/bullet.rb
if Rails.env.development? && defined?(Bullet)
  Bullet.enable = true
  Bullet.rails_logger = true
  Bullet.stacktrace_includes = [ 'spree_core', 'spree_frontend', 'spree_api', 'spree_backend', 'spree_emails' ]
end
RUBY

cat <<YML > config/database.yml
# MySQL. Versions 5.5.8 and up are supported.
#
# Install the MySQL driver:
#   gem install activerecord-jdbcmysql-adapter
#
# Configure Using Gemfile
# gem 'activerecord-jdbcmysql-adapter'
#
# And be sure to use new-style password hashing:
#   https://dev.mysql.com/doc/refman/5.7/en/password-hashing.html
#
default: &default
  adapter: mysql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: $DB_USER
  password: '$DB_PASS'
  host: localhost

development:
  <<: *default
  database: spree_development

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test:
  <<: *default
  database: spree_test

# As with config/credentials.yml, you never want to store sensitive information,
# like your database password, in your source code. If your source code is
# ever seen by anyone, they now have access to your database.
#
# Instead, provide the password or a full connection URL as an environment
# variable when you boot the app. For example:
#
#   DATABASE_URL="mysql://myuser:mypass@localhost/somedatabase"
#
# If the connection URL is provided in the special DATABASE_URL environment
# variable, Rails will automatically merge its configuration values on top of
# the values provided in this file. Alternatively, you can specify a connection
# URL environment variable explicitly:
#
#   production:
#     url: <%= ENV['MY_APP_DATABASE_URL'] %>
#
# Read https://guides.rubyonrails.org/configuring.html#configuring-a-database
# for a full overview on how database connection configuration can be specified.
#
production:
  <<: *default
  database: $DB_NAME
YML

bundle install --gemfile Gemfile

export RAILS_ENV=production
bundle exec rails db:drop || true
bundle exec rails db:create

bundle exec rake railties:install:migrations
bundle exec rails db:migrate
# bundle exec rails db:seed
# bundle exec rake spree_sample:load

set_auto_increment_start() (
  index=0
  for table in $(sudo mysqlshow spree_production | grep '| spree_' | cut -d' ' -f2 | sort)
  do
    index=$((index+1000000))
    mysql --defaults-extra-file=<(printf "[client]\nuser = %s\npassword = %s" "$DB_USER" "$DB_PASS") -D "$DB_NAME" -e "ALTER TABLE $table AUTO_INCREMENT=$index"
  done
)
set_auto_increment_start

bundle exec rails g spree:install --auto-accept --user_class=Spree::User --sample=true
if [ "$SPREE_HEADLESS" = "" ]; then
  bundle exec rails g spree:frontend:install
  bundle exec rails g spree:backend:install
  bundle exec rails g spree:emails:install
fi
bundle exec rails g spree:auth:install
bundle exec rails g spree_gateway:install

cat <<RUBY >> config/puma.rb
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 16)
threads threads_count, threads_count

app_dir = File.expand_path("../..", __FILE__)
shared_dir = "#{app_dir}/shared"

bind "unix://#{shared_dir}/sockets/puma.sock"

stdout_redirect "#{shared_dir}/log/puma.stdout.log", "#{shared_dir}/log/puma.stderr.log", true

pidfile "#{shared_dir}/pids/puma.pid"
state_path "#{shared_dir}/pids/puma.state"
activate_control_app

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RAILS_ENV'] || 'development'
RUBY

mkdir shared/log
mkdir shared/pids
mkdir shared/sockets

bundle exec rake assets:precompile
