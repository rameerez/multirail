# 🚝 multirail

**Deploy multiple Rails app to the same Linux (Ubuntu) server using nginx, Puma and Capistrano.**

[Stop paying hundreds of dollars to AWS](https://x.com/rameerez/status/1811782548353351898), Heroku and similar services! Host multiple Rails apps in a single VPS Ubuntu server with a single command.

> ⚠️ WARNING: This is a prototype – I created it to deploy my own Rails projects. It may NOT be production ready.

# Pre-requisites

You need an already working Rails app, ready to deploy, and using __the same Ruby version as your server__. Also, you need to be using a `postgresql` db and adapter.

# Server requirements

> 💡 You can just run [this script](https://gist.github.com/rameerez/4813291ad6e21766e05718a961276341) I created to set up a new Ubuntu Server 22.04 LTS machine and get it ready to accept Rails apps via Capistrano. You may need to run something like this afterwards: [post-setup script](https://gist.github.com/rameerez/a9fa4e78bebe7caf91fced41d781d60f)

I really really recommend you use the script I provided above. If you'd rather set up your own server manually: you need a target production Linux server you can `ssh` into, with a user with `nopasswd` sudo access, and with the following stuff installed: `ruby`, `rvm`, `bundler`, `certbot`, `nginx`, `psql`, `git` (the recommended option is to spin up a that has all this already installed). If you're using private Git repos, make sure your server has access to those via ssh (how-to in the following setup instructions).

Minimum server requirements: 2vCPUs, 4GB RAM. Modern Rails apps might crash with fewer resources, even if small.

# Add a GitHub ssh key to your server

If you're using a private GitHub repo, make your server talk with your Git server via `ssh`:

   - Create a ssh key on your Linux server using the email you use to log in to GitHub.

   `ssh-keygen -t rsa -b 4096 -C "your-github-email@email.com"`

   - Make sure your ssh agent is running

   `eval "$(ssh-agent -s)"`

   - Add your new ssh key (assuming you didn't specify a custom key name, so the key name is the default `id_rsa`)

   `ssh-add ~/.ssh/id_rsa`

   - Show the public key content so you can copy it (again, assuming default key name `id_rsa`):

   `cat ~/.ssh/id_rsa.pub`

   - Go to GitHub.com > Settings > SSH and GPG keys > New SSH key. Add a human-readable title like "Ubuntu production server at 1.2.3.4", paste in your public key you had just copied and hit "Add SSH key"

# Usage

On your local development machine clone Multirail to any location with `git clone https://github.com/rameerez/multirail.git && cd multirail`

Then just execute this (MAKE SURE you REPLACE your own values!):

```
./multirail -d yourdomain.com -i 123.123.123.123 -u rails -g git@github.com:your_github_username/your_rails_repo.git -n your_rails_app_name -f /path/to/your/local/rails/app -v 3.2.3
```

Where:

- `yourdomain.com` is the domain you wish to deploy your app to.
- `123.123.123.123` the IP address of your server.
- `rails` is the Linux user in your server that will be used to deploy.
- `git@github.com:your_github_username/your_rails_repo.git` is the Git SSH URL of your repository from which Capistrano will pull the code.
- `your_rails_app_name` is just the name of your app (best to name it equal to your repo). [⚠️ IMPORTANT: due to a bug, please don't use any non-letter characters or spaces in the name. Just letters. Or else Postgresql will fail to create the user]
- `/path/to/your/local/rails/app` is the path on your local machine where the Rails project is.
- `3.2.3` is the Ruby version both your project and your server are using.

For more info, execute `./multirail -h`

---

*🚨 Important*
After this, you need to `ssh` into your server and create your `/home/rails/apps/your_rails_app_name/shared/config/master.key` file with the same contents as the dev file so the Rails secrets file can be decoded in the server.

You're done! Import your PostgreSQL data (if any) and you're ready to go! ✨ Now go to your domain and verify everything is working flawlessly and with a shiny 🔒 SSL cert!

# Known issues
 - App names must NOT contain any non-letter characters or spaces. Name your apps "myapp" (all together, no spaces) instead of "my-app"
 - The `puma` version in the Rails' project Gemfile must be kept at `~> 4.0` because they got rid of the daemon mode on v5 and the new `systemctl` services don't work under our current setup, this is a big TODO for this project

# To-do

- [ ] Revert unsuccessfull installations
- [ ] Completely remove an app from the server

# Troubleshooting

## `LOCALE` errors
If you're getting weird LOCALE errors, you might need to stop accepting remote locale on the server by commenting out the `AcceptEnv LANG LC_*` line in the _remote_ (server) `/etc/ssh/sshd_config` file.

## Server with an ARM architecture

If your server is x86_64 (Intel / AMD), you may want to run:
```
bundle lock --add-platform x86_64-linux
bundle lock --add-platform ruby
```

If your server is ARM64, you may want to run:
```
bundle lock --add-platform aarch64-linux
bundle lock --add-platform ruby
```

In any case, make sure your server architecture (like `x86_64-linux`) and `ruby` are added to your local Gemfile.lock, or the deployment script will complain and interrupt in the first deployment.

## Database server not running

If the database server is not working:

`ssh` into the server and check that `puma` is running

```
ps aux | grep puma
```

Then you should see at least one process that's running on an unix sock. It should be the same sock as configured in the `deploy.rb` script. Example output:

```
rails      848  0.0  6.5 803396 66228 ?        Ssl  May03   9:30 puma 3.12.0 (tcp://0.0.0.0:3000) [example]
rails     4683  0.0 13.0 864652 131388 ?       Sl   May14   5:13 puma 3.12.1 (unix:///home/rails/apps/app1/shared/tmp/sockets/app1-puma.sock)
rails    25487  3.6  9.2 847816 93244 ?        Sl   08:57   0:03 puma 3.12.0 (unix:///home/rails/apps/app2/shared/tmp/sockets/app2-puma.sock)
rails    25525  0.0  0.1  11464  1152 pts/0    S+   08:58   0:00 grep --color=auto puma
```

## Rails app not running

If the required app is not running, check if it has a valid pid (or any at all). `cd` to the app dir (`cd ~/apps/APPNAME`) and `ls` the `pids` folder in search of the `puma.pid`:

```
ls shared/tmp/pids/
```

If `puma.pid` is not in the output, the puma server is down.

From the local dev environment, cd to the rails project and spin it up with:

```
bundle exec cap production deploy:restart
```

This should create the `puma.pid` and `ps aux | grep puma` should now output our process. We may also try

```
bundle exec cap production puma:restart
```

if that's not enough.

# How to uninstall sites

 1. `ssh` into the server
 2. Delete the directory the Rails app was deployed to `/apps/your_rails_app_name`
 3. Delete any related Postgres databases
      ```
      sudo su - postgres
      psql
      \l
      DROP DATABASE <your_rails_app_name>_production;
      ```
 4. See what's on nginx config `ls -lah /etc/nginx/sites-enabled/`
 5. Remove the sites that are no longer present `rm /etc/nginx/sites-enabled/your_rails_app_name`
 6. Restart nginx `sudo service nginx restart`
 7. See what's on Letsencrypt `sudo ls /etc/letsencrypt/live`
 8. Remove the site from Letsencrypt `sudo rm -rf /etc/letsencrypt/live/your_rails_app_name`