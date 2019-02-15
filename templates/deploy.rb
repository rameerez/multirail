# config valid for current version and patch releases of Capistrano
lock "~> 3.11.0"

# Change these
server '$IP_ADDRESS', roles: [:web, :app, :db], primary: true

set :repo_url,        "$GIT_REPO_URL_SSH"
set :application,     '$APP_NAME'
set :user,            '$USER_REMOTE_LINUX'
set :puma_threads,    [4, 16]
set :puma_workers,    0


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
# set :branch,        :master
# set :format,        :pretty
# set :log_level,     :debug
# set :keep_releases, 5

## Linked Files & Directories (Default None):
# set :linked_files, %w{config/database.yml}
# set :linked_dirs,  %w{bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}

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
      unless `git rev-parse HEAD` == `git rev-parse origin/master`
        puts "WARNING: HEAD is not the same as origin/master"
        puts "Run `git push` to sync changes."
        exit
      end
    end
  end

  desc 'Initial Deploy'
  task :initial do
    on roles(:app) do
      execute 'sudo -u postgres bash -c "psql -c \"CREATE USER $APP_NAME WITH PASSWORD \'$RANDOM_DATABASE_PASSWORD\';\""'
      execute "sudo -u postgres psql -c 'create database $APP_NAME_production;'"
      execute "sudo -u postgres psql -c 'grant all privileges on database $APP_NAME_production to $APP_NAME;'"
      execute "sudo -u postgres psql -c 'ALTER DATABASE $APP_NAME_production OWNER TO $APP_NAME;'"

      execute "mkdir -p /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config"
      execute "touch /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/secrets.yml"
      secrets_content="production:\n  secret_key_base: $RAKE_SECRET"
      execute "echo '#{secrets_content}' >> /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/database.yml"

      execute "touch /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/database.yml"
      database_config = "production:\n  adapter: postgresql\n  database: $APP_NAME_production\n  username: $APP_NAME\n  password: $RANDOM_DATABASE_PASSWORD"
      execute "echo '#{database_config}' >> /home/#{fetch(:user)}/apps/#{fetch(:application)}/shared/config/database.yml"

      before 'deploy:restart', 'puma:start'
      invoke 'deploy'
    end
  end

  desc 'Link nginx configuration'
  task :symlink_nginx_conf do
    on roles(:app) do
      execute "sudo rm /etc/nginx/sites-enabled/default"
      execute "sudo ln -nfs /home/$USER_REMOTE_LINUX/apps/$APP_NAME/current/config/nginx.conf /etc/nginx/sites-enabled/$APP_NAME"
      execute "sudo service nginx start"
    end
  end
  
  desc 'Create SSL cert'
  task :create_ssl_cert do
    on roles(:app) do
      execute "[ ! -f /etc/letsencrypt/live/$DOMAIN ] && sudo certbot --nginx --agree-tos --redirect --hsts --uir -n -m admin@$DOMAIN -d $DOMAIN && sudo service nginx restart"
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      invoke 'puma:restart'
    end
  end

  before :starting,     :check_revision
  after  :finishing,    :compile_assets
  after  :finishing,    :cleanup
  after  :finishing,    :symlink_nginx_conf
  after  :finishing,    :create_ssl_cert
  after  :finishing,    :restart
end

# ps aux | grep puma    # Get puma pid
# kill -s SIGUSR2 pid   # Restart puma
# kill -s SIGTERM pid   # Stop puma


append :linked_files, "config/database.yml"
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads"