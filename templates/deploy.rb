# config valid for current version and patch releases of Capistrano
lock "~> 3.18.0"
# # Change these
# server '$IP_ADDRESS', roles: [:web, :app, :db], primary: true

set :repo_url,        "$GIT_REPO_URL_SSH"
set :application,     '$APP_NAME'
set :user,            '$USER_REMOTE_LINUX'
# set :puma_threads,    [4, 16]
# set :puma_workers,    0


# Don't change these unless you know what you're doing
set :pty,             true
set :use_sudo,        false
set :stage,           :production
set :deploy_via,      :remote_cache
set :deploy_to,       "/home/#{fetch(:user)}/apps/#{fetch(:application)}"
set :puma_bind,       "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"
set :puma_state,      "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,        "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log, "#{release_path}/log/puma.error.log"
set :puma_error_log,  "#{release_path}/log/puma.access.log"
set :ssh_options,     { forward_agent: true, user: fetch(:user), keys: %w(~/.ssh/id_rsa.pub) }
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_init_active_record, false  # Change to true if using ActiveRecord

## Defaults:
# set :scm,           :git
# set :branch,        :main
# set :format,        :pretty
# set :log_level,     :debug
# set :keep_releases, 5

## Linked Files & Directories (Default None):
# set :linked_files, %w{config/database.yml}
# set :linked_dirs,  %w{bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}

# Allow to run `rails c` by running `cap [staging] rails:console`
# or `cap [staging] rails:console 1` if you have more than 1 server in your server list
# Source: https://stackoverflow.com/questions/9569070/how-to-enter-rails-console-on-production-via-capistrano

namespace :rails do
  desc 'Open a rails console `cap [staging] rails:console [server_index default: 0]`'
  task :console do
    server = roles(:app)[ARGV[2].to_i]

    puts "Opening a console on: #{server.hostname}...."

    cmd = "ssh -l #{fetch(:user)} #{server.hostname} -t 'source ~/.rvm/scripts/rvm && cd #{fetch(:deploy_to)}/current && RAILS_ENV=#{fetch(:rails_env)} bundle exec rails console'"

    puts cmd

    exec cmd
  end
end

namespace :puma do
  desc 'Create Directories for Puma Pids and Socket'
  task :make_dirs do
    on roles(:app) do
      execute "mkdir #{shared_path}/tmp/sockets -p"
      execute "mkdir #{shared_path}/tmp/pids -p"
    end
  end

  before :start, :make_dirs
end

namespace :deploy do
  desc "Make sure local git is in sync with remote."
  task :check_revision do
    on roles(:app) do
      unless `git rev-parse HEAD` == `git rev-parse origin/main`
        puts "WARNING: HEAD is not the same as origin/main"
        puts "Run `git push` to sync changes."
        exit
      end
    end
  end

  desc 'Initial Deploy'
  task :initial do
    on roles(:app) do
      # TODO: figure out how to escape $APP_NAME using double quotes because this breaks if $APP_NAME contains hyphens like my-app
      execute 'sudo -u postgres bash -c "psql -c \"CREATE USER $APP_NAME WITH PASSWORD \'$RANDOM_DATABASE_PASSWORD\';\""'
      execute "sudo -u postgres psql -c 'create database $APP_NAME_production;'"
      execute "sudo -u postgres psql -c 'grant all privileges on database $APP_NAME_production to $APP_NAME;'"
      execute "sudo -u postgres psql -c 'ALTER DATABASE $APP_NAME_production OWNER TO $APP_NAME;'"

      execute "mkdir -p /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config"
      execute "touch /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/secrets.yml"

secrets_content = %x(
base64 <<TEST
production:
  secret_key_base: $RAKE_SECRET
TEST
).delete("\n")
      execute "echo '#{secrets_content}' | base64 -d | cat - >> /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/secrets.yml"

      execute "touch /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/database.yml"

database_config = %x(
base64 <<TEST
production:
  adapter: postgresql
  host: localhost
  database: $APP_NAME_production
  username: $APP_NAME
  password: $RANDOM_DATABASE_PASSWORD
TEST
).delete("\n")
      execute "echo '#{database_config}' | base64 -d | cat - >> /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/database.yml"

      before 'deploy:restart', 'puma:start'
      invoke 'deploy'
    end
  end

  desc 'Link nginx configuration'
  task :symlink_nginx_conf do
    on roles(:app) do
      nginx_config = <<-EOS
upstream puma_#{fetch(:application)} {
  server unix://#{fetch(:deploy_to)}/shared/tmp/sockets/#{fetch(:application)}-puma.sock;
}

# Actual site server block
server {
  listen 80;
  server_name #{fetch(:domain_name)};

  root #{fetch(:deploy_to)}/current/public;
  access_log #{fetch(:deploy_to)}/current/log/nginx.access.log;
  error_log #{fetch(:deploy_to)}/current/log/nginx.error.log info;

  location ^~ /assets/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }

  try_files $uri/index.html $uri @puma_#{fetch(:application)};
  location @puma_#{fetch(:application)} {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    # Adding more headers to prevent Rails complaining about "ActionController::InvalidAuthenticityToken (ActionController::InvalidAuthenticityToken):"
    # because "HTTP Origin header (...) didn't match request.base_url (...)"
    # source: https://github.com/rails/rails/issues/22965
    proxy_set_header  X-Forwarded-Proto $scheme;
    proxy_set_header  X-Forwarded-Ssl on; # Optional
    proxy_set_header  X-Forwarded-Port $server_port;
    proxy_set_header  X-Forwarded-Host $host;

    proxy_redirect off;

    proxy_pass http://puma_#{fetch(:application)};
  }

  location /cable {
    proxy_pass http://puma_#{fetch(:application)};
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Ssl on; # Optional
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header X-Forwarded-Host $host;
    proxy_redirect off;
  }

  error_page 500 502 503 504 /500.html;
  client_max_body_size 10M;
  keepalive_timeout 10;
}
EOS

      nginx_config_encoded = Base64.strict_encode64(nginx_config).gsub("\n", '')

      execute :echo, "'#{nginx_config_encoded}'", '|', :base64, '-d', '|', :tee, "#{fetch(:deploy_to)}/shared/config/nginx.conf", '>', '/dev/null'

      execute "sudo ln -nfs #{fetch(:deploy_to)}/shared/config/nginx.conf /etc/nginx/sites-enabled/#{fetch(:application)}"

      execute "sudo service nginx start"
    end
  end

  desc 'Create SSL cert'
  task :create_ssl_cert do
    on roles(:app), wait: 15 do
      execute "[ ! -f /etc/letsencrypt/live/$DOMAIN ] && sudo certbot --nginx --agree-tos --redirect --hsts -n -m admin@$DOMAIN -d $DOMAIN && sudo service nginx restart"
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      invoke 'puma:restart'
    end
  end

  desc 'Update sidekiq.service config file'
  task :update_sidekiq_service_config do
    on roles(:app), in: :sequence, wait: 5 do
      execute "mkdir -p /home/#{fetch(:user)}/.config/systemd/user"

      sidekiq_service = <<-EOS
#
# This file tells systemd how to run Sidekiq as a 24/7 long-running daemon.
#
# Customize this file based on your bundler location, app directory, etc.
#
# If you are going to run this as a user service (or you are going to use capistrano-sidekiq)
# Customize and copy this to ~/.config/systemd/user
# Then run:
#   - systemctl --user enable sidekiq
#   - systemctl --user {start,stop,restart} sidekiq
#
# If you are going to run this as a system service
# Customize and copy this into /usr/lib/systemd/system (CentOS) or /lib/systemd/system (Ubuntu).
# Then run:
#   - systemctl enable sidekiq
#   - systemctl {start,stop,restart} sidekiq
#
# This file corresponds to a single Sidekiq process.  Add multiple copies
# to run multiple processes (sidekiq-1, sidekiq-2, etc).
#
# Use `journalctl -u sidekiq -rn 100` to view the last 100 lines of log output.
#
[Unit]
Description=sidekiq
# start us only once the network and logging subsystems are available,
# consider adding redis-server.service if Redis is local and systemd-managed.
After=syslog.target network.target

# See these pages for lots of options:
#
#   https://www.freedesktop.org/software/systemd/man/systemd.service.html
#   https://www.freedesktop.org/software/systemd/man/systemd.exec.html
#
# THOSE PAGES ARE CRITICAL FOR ANY LINUX DEVOPS WORK; read them multiple
# times! systemd is a critical tool for all developers to know and understand.
#
[Service]
#
#      !!!!  !!!!  !!!!
#
# As of v6.0.6, Sidekiq automatically supports systemd's `Type=notify` and watchdog service
# monitoring. If you are using an earlier version of Sidekiq, change this to `Type=simple`
# and remove the `WatchdogSec` line.
#
#      !!!!  !!!!  !!!!
#
Type=simple
# If your Sidekiq process locks up, systemd's watchdog will restart it within seconds.
# WatchdogSec=10

WorkingDirectory=#{fetch(:deploy_to)}/current
# If you use rbenv:
# ExecStart=/bin/bash -lc 'exec /home/deploy/.rbenv/shims/bundle exec sidekiq -e production'
# If you use the system's ruby:
# ExecStart=/usr/local/bin/bundle exec sidekiq -e production
# If you use rvm in production without gemset and your ruby version is 2.6.5
# ExecStart=/home/deploy/.rvm/gems/ruby-2.6.5/wrappers/bundle exec sidekiq -e production
# If you use rvm in production with gemset and your ruby version is 2.6.5
# ExecStart=/home/deploy/.rvm/gems/ruby-2.6.5@gemset-name/wrappers/bundle exec sidekiq -e production
# If you use rvm in production with gemset and ruby version/gemset is specified in .ruby-version,
# .ruby-gemsetor or .rvmrc file in the working directory
# ExecStart=/home/#{fetch(:user)}/.rvm/bin/rvm in #{fetch(:deploy_to)}/current do bundle exec sidekiq -c 10 -e #{fetch(:stage).to_s} >> #{fetch(:deploy_to)}/current/log/sidekiq.log
ExecStart=/bin/bash -lc 'cd #{fetch(:deploy_to)}/current && bundle exec sidekiq -q #{fetch(:sidekiq_app_queue)} -q default -q mailers -c 10 -e #{fetch(:stage).to_s} >> #{fetch(:deploy_to)}/current/log/sidekiq.log'

# Use `systemctl kill -s TSTP sidekiq` to quiet the Sidekiq process

# Uncomment this if you are going to use this as a system service
# if using as a user service then leave commented out, or you will get an error trying to start the service
# !!! Change this to your deploy user account if you are using this as a system service !!!
# User=deploy
# Group=deploy
# UMask=0002

# Greatly reduce Ruby memory fragmentation and heap usage
# https://www.mikeperham.com/2018/04/25/taming-rails-memory-bloat/
Environment=MALLOC_ARENA_MAX=2

# if we crash, restart
RestartSec=1
Restart=on-failure

# output goes to /var/log/syslog (Ubuntu) or /var/log/messages (CentOS)
StandardOutput=syslog
StandardError=syslog

# This will default to "bundler" if we don't specify it
SyslogIdentifier=sidekiq

[Install]
WantedBy=multi-user.target
EOS

      sidekiq_service_encoded = Base64.strict_encode64(sidekiq_service).gsub("\n", '')

      execute :echo, "'#{sidekiq_service_encoded}'", '|', :base64, '-d', '|', :tee, "/home/#{fetch(:user)}/.config/systemd/user/sidekiq.service", '>', '/dev/null'

      execute "systemctl --user daemon-reload"
    end
  end

  desc 'Restart Sidekiq'
  task :restart_sidekiq do
    on roles(:app), in: :sequence, wait: 5 do
      execute "systemctl --user restart sidekiq"
    end
  end

  desc 'Print summary of deployment ahead'
  task :print_summary_before_deployment do
    on roles(:app) do
      execute "echo 'STARTING DEPLOYMENT'"
      execute "echo 'Stage: #{fetch(:stage)}'"
      execute "echo 'Domain: #{fetch(:domain_name)}'"
      execute "echo 'Branch: #{fetch(:branch)}'"
      execute "echo 'DB endpoint: #{fetch(:default_env)['DB_HOST']}'"
    end
  end

  before :starting,     :print_summary_before_deployment
  before :starting,     :check_revision
  # after  :finishing,    :compile_assets
  after  :finishing,    :cleanup
  after  :finishing,    :symlink_nginx_conf
  after  :finishing,    :create_ssl_cert
  after  :finishing,    :restart
  after  :finishing,    :update_sidekiq_service_config
  after  :finishing,    :restart_sidekiq
end

# ps aux | grep puma    # Get puma pid
# kill -s SIGUSR2 pid   # Restart puma
# kill -s SIGTERM pid   # Stop puma


append :linked_files, "config/database.yml", "config/secrets.yml"
# https://stackoverflow.com/questions/50963676/rails-5-2-with-master-key-digital-ocean-deployment-activesupportmessageencryp
append :linked_files, "config/master.key"
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads"
