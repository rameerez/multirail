# 🚝 multirail

Set up and configure multiple Rails app in the same DigitalOcean droplet / Linux (Ubuntu) server using nginx, Puma and Capistrano.

Stop paying hundreds of dollars to Heroku and similar services! Host multiple Rails apps in a single Linux server with ease and minimal config. All this with a free, ready-to-use SSL certificate! Multirail removes the frustration out of the process.

Designed to work with a [DigitalOcean](https://m.do.co/c/b6d95cc978e4) one-click Rails droplet.

[⚠️ WARNING]: This is still a really rough prototype – I only created it to help myself deploy my rails projects. I wouldn't recommend using it in real production environments cuz it might be buggy and not very secure and all that (even though I use it for my production apps) Please contribute to improve the project!

# Pre-requisites

You need an already working Rails app, ready to deploy, and using the same Ruby version as your server. Also you need to be using a `postgresql` db and adapter.

You need a target production Linux server you can `ssh` into, with a user with `nopasswd` sudo access, and with the following stuff installed: `ruby`, `rvm`, `bundler`, `certbot`, `nginx`, `psql`, `git` (the recommended option is to spin up a [Rails DigitalOcean droplet](https://m.do.co/c/b6d95cc978e4) that has all this already installed). If you're using private Git repos, make sure your server has access to those via ssh (how-to in the following setup instructions).

## Pre-requisites quick setup

1. [Spin up a Rails DigitalOcean droplet](https://m.do.co/c/b6d95cc978e4) using the Ruby on Rails one-click setup.

Sign up > Click the "Create" button on the upper right corner > Droplets > One-click apps > Select "Ruby-on-Rails on XX.XX" > Choose a droplet size > Choose a datacenter region > Create

Alternatively, and we highly recommend against this, set up your own Linux server with Ruby, rvm, Bundler, nginx, postgresql and all required packages using a guide like [this one](https://gorails.com/deploy/ubuntu/18.04) (not recommended, a DigitalOcean Rails one-click droplet removes all that hassle).

From now on, use your `rails` Linux user, not `root`.

2. Check your Rails project uses the exact same Ruby version as your server

Check the `Gemfile` on your Rails project and either change the Ruby version to the one on the server and verify everything still works or install that exact Ruby version on the server with `rvm install x.y.z` and then tell the server to use that version by default by running `rvm use system x.y.z` or `rvm x.y.z --default`

Also check you're using a `postgresql` adapter in your `database.yml` (in production, at least)

3. If you're using private Git repos: Make your server talk with your Git server via `ssh`. We'll assume you're using private GitHub repos:

   - Create a ssh key on your Linux server using the email you use to log in to GitHub.

   `ssh-keygen -t rsa -b 4096 -C "your-github-email@email.com"`

   - Make sure your ssh agent is running

   `eval "$(ssh-agent -s)"`

   - Add your new ssh key (assuming you didn't specify a custom key name, so the key name is the default `id_rsa`)

   `ssh-add ~/.ssh/id_rsa`

   - Show the public key content so you can copy it (again, assuming default key name `id_rsa`):

   `cat ~/.ssh/id_rsa.pub`

   - Go to GitHub.com > Settings > SSH and GPG keys > New SSH key. Add a human-readable title like "production server", paste in your public key you had just copied and hit "Add SSH key"

4. You'll need to configure `nopasswd` sudo access for the user you'll use for deploying (Capistrano 3 doesn't allow password prompting). Assuming your user is the default `rails` in DigitalOcean, execute:
   `sudo nano /etc/sudoers`
   And add `rails ALL=(ALL) NOPASSWD:ALL` right before `#includedir /etc/sudoers.d`

5. If you're getting weird LOCALE errors, you might need to stop accepting remote locale on the server by commenting out the `AcceptEnv LANG LC_*` line in the _remote_ (server) `/etc/ssh/sshd_config` file.

# Usage

On your local development machine clone Multirail to the location you desire with `git clone https://github.com/rameerez/multirail.git && cd multirail`

Then just execute (substitute with your own values!):

```
./multirail -d example.com -i 123.123.123.123 -u rails -g git@github.com:rameerez/my-app.git -n my-app -f ~/git/my-app -v 2.4.0
```

Where:

- `example.com` is the domain you wish to deploy your app to.
- `123.123.123.123` the IP address of your server.
- `rails` is the Linux user in your server that will be used to deploy.
- `git@github.com:rameerez/my-app.git` is the Git SSH URL of your repository from which Capistrano will pull the code.
- `my-app` is just the name of your app (best to name it equal to your repo).
- `~/git/my-app` is the path on your local machine where the Rails project is.
- `2.4.0` is the Ruby version both your project and your server are using.

For more info, execute `./multirail -h`

---

You're done! Import your PostgreSQL data (if any) and you're ready to go! ✨ Now go to your domain and verify everything is working flawlessly and with a shiny 🔒 SSL cert!

# Troubleshooting

If one of the servers is not working:

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

# To-do

- [ ] Don't create DB role and database if already created (from a failed installation, or from trying to redeploy)
- [ ] Revert unsuccessfull installations
- [ ] Completely remove an app from the server
