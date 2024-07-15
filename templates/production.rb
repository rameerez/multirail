# config/deploy/production.rb

set :stage,               :production

server '$IP_ADDRESS',     roles: [:web, :app, :db], primary: true

set :domain_name,         "$DOMAIN"

set :branch,              'main'

set :puma_threads,        [4, 16]
set :puma_workers,        0

set :sidekiq_app_queue,   "$APP_NAME_production_default"
