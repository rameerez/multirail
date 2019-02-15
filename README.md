# 🚝 multirail

Set up and configure multiple Rails app in the same DigitalOcean droplet / Linux (Ubuntu) server using nginx, Puma and Capistrano.

Stop paying hundreds of dollars to Heroku and similar services! Host multiple Rails apps in a single Linux server with ease and minimal config. All this with a free, ready-to-use SSL certificate! Multirail removes the frustration out of the process.

Designed to work with a [DigitalOcean](https://m.do.co/c/b6d95cc978e4) one-click Rails droplet.

# Pre-requisites

You need an already working Rails app, ready to deploy, and using the same Ruby version as your server.

You need a target production Linux server you can `ssh` into, with the following stuff installed: `ruby`, `rvm`, `bundler`, `certbot`, `nginx`, `psql`, `git` (the recommended option is to spin up a [Rails DigitalOcean droplet](https://m.do.co/c/b6d95cc978e4) that has all this already installed). If you're using private Git repos, make sure your server has access to those via ssh (how-to in the following setup instructions).

## Pre-requisites quick setup

1. [Spin up a Rails DigitalOcean droplet](https://m.do.co/c/b6d95cc978e4) using the Ruby on Rails one-click setup.

Sign up > Click the "Create" button on the upper right corner > Droplets > One-click apps > Select "Ruby-on-Rails on XX.XX" > Choose a droplet size > Choose a datacenter region > Create

Alternatively, and we highly recommend against this, set up your own Linux server with Ruby, rvm, Bundler, nginx, postgresql and all required packages using a guide like [this one](https://gorails.com/deploy/ubuntu/18.04) (not recommended, a DigitalOcean Rails one-click droplet removes all that hassle).

From now on, use your `rails` Linux user, not `root`.

2. Check your Rails project uses the exact same Ruby version as your server

Check the `Gemfile` on your Rails project and either change the Ruby version to the one on the server and verify everything still works or install that exact Ruby version on the server with `rvm install x.y.z` and then tell the server to use that version by default by running `rvm use system x.y.z` or `rvm x.y.z --default`

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

# Usage

1. On your local development machine, `cd` to the Rails project you want to deploy and:

   - `git clone https://github.com/rameerez/multirail.git && cd multirail`
   - `sudo multirail`

2. On your production server, ssh in with the `rails` user (or whichever user you're using to deploy) and:

   - `git clone https://github.com/rameerez/multirail.git && cd multirail`
   - todo: remote script usage

3. Import your PostgreSQL data (if any) and you're ready to go! ✨ Now go to your domain and verify everything is working flawlessly and with a shiny 🔒 SSL cert!
