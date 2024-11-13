# Production-ready Moodle with docker compose

What are provided in this stack:
- A version of moodle of your choice, hosted inside official PHP docker with FPM enabled
- Postgresql PDO enabled
- Nginx as reverse proxy with `XSendfile/X-Accel-Redirect` enabled for serving file
- SSL certificate issuance and renewal with certbot

## What compose file should I use?
- For http deployment, use `docker-compose.dev.yaml`
- For testing and debugging SSL issuance/renewal, use `docker-compose.ssl.yaml`
- For staging mode (e.g. in VM), use `docker-compose.staging.yaml`

#### Production use
For production, ideally you may want to copy `docker-compose.staging.yaml` to `docker-compose.production.yaml`, 
modify it as needed and keep them without adding it back to git.

You may also need to adjust the database connection and `wwwroot` accordingly:
```
    environment:
      - DB_HOST=database
      - DB_PORT=5432
      - DB_NAME=moodle
      - DB_USER=user
      - DB_PASSWORD=password
      - WWW_ROOT=https://example.com
```

## Understanding the directories

- `certbot`: contains certbot container data related to ssl certificate issuance and renewal
- `moodle`: contains moodle source code, which you manually bring a version of your choice inside this folder
- `moodle-data`: contains moodle data that will be shared inside `nginx` and `moodle` _container_
- `moodle-plugins`: contains moodle plugins and will be inserted inside `moodle` folder on build
- `nginx`: contains nginx configuration for both http and https scenario

## Installing

### Checks
- A local device or VM with any OS (we use Ubuntu 20.04 LTS)
- install git
- install docker (`compose` should also be included already)
- enable cron service (e.g. `service cron status|enable`)

### Preparation
- Clone this repo
- Set permission to `moodle-data` directory ([why is 777 needed?](https://docs.moodle.org/405/en/Installing_Moodle#:~:text=(not%20recommended)-,Create%20the%20(moodledata)%20data%20directory,-Moodle%20requires%20a))

  ```
  sudo chmod -R 0777 moodle-data
  ```

- Bring your moodle source code
  - choose one that fit best: 
    - [download from the official github repo](https://github.com/moodle/moodle/tags)
    - [download from the official website](https://download.moodle.org/)
    - manually clone it from github repo
      - [pick the branch](https://github.com/moodle/moodle/branches)
      - clone it inside `moodle` folder. For example, we use version 4.5.0

        ```
        cd moodle
        rm .gitkeep
        git clone -b MOODLE_405_STABLE https://github.com/moodle/moodle.git .
        ```
  - Copy or move `Dockerfile` from root repository inside `moodle` folder  
  - no matter what option you picked, the resulting directory should be like this. Note that all moodle source code are placed directly inside the `moodle` folder

    ```
    moodle (repository root)/
    ├── certbot
    ├── moodle (moodle source root)/
    │   ├── Dockerfile
    │   ├── admin
    │   ├── ai
    │   ├── analytics
    │   ├── auth
    │   ├── availability
    │   └── ... (and so on)
    ├── moodle-data
    ├── moodle-plugins
    ├── nginx
    └── ...
    ```

### Configuration

#### Configuring `config.php`

Please change `moodle_config.php` according to your need. You can find it on the root of this repository.
By default, it already has:
- database configuration and `wwwroot` being configured to read from environment variables (specified inside the compose file)
- `XSendfile` enabled

On build time, this file will be inserted as `config.php` inside the `moodle` directory.

#### Configuring `php.ini`

You may also want to configure the PHP-FPM behavior. To do this, please modify `moodle_docker-fpm.ini` as needed.

On build time, this file will be inserted as `docker-fpm.ini` inside the `moodle` directory to replace the original configuration.


#### Changing file upload size

- On `moodle_docker-fpm.ini`:
```
; Change upload size permissions
; Maximum allowed size for uploaded files.
upload_max_filesize = 40M
; Must be greater than or equal to upload_max_filesize
post_max_size = 50M
```

- On `nginx/https.conf`:
```
client_max_body_size 60M;
```

_Note_: You may need to do `docker compose up -d --build --force-recreate` to make sure the new configuration being applied.

### Spinning up the stack

Use any of the compose file for your need and spin them up.

```
docker compose -f docker-compose.production.yaml up -d
```

#### Post-spin-up checks

- Test that the stack can serve static file properly. If you are on http stack, open this link on a browser:
  ```
  http://localhost/pix/moodlelogo.png
  ```

  or in https (assuming certificates are already configured)

  ```
  https://example.com/pix/moodlelogo.png
  ```

  By examining the docker logs, we can see that the `moodle` container returns 0 byte,
  while the nginx container with the same link returns some bytes.
  This proves that `X-Accel-Redirect` is working.

- If this is your first time installing moodle then a copyright page will appear, continued by dependencies page.
Make sure that all dependencies are met, and continue the installation process.
- After creating the admin, the installation process is finished.

### Final configuration
You may want to do [final configuration](https://docs.moodle.org/405/en/Installing_Moodle#:~:text=on%2Dscreen%20instructions.-,Final%20configuration,-Settings%20within%20Moodle) to your moodle site.

## SSL Issuance and renewal

### Issuing certificate for the first time
- Spin up the stack. You can use `ssl` or `staging` yaml: `docker compose -f docker-compose.ssl.yaml up`
- Notice that we omit the `-d` parameter, so the logs stays on terminal during the up session
- You will notice that `cerbot` is immediately exited, it's fine
- With other terminal, run a certbot issuance in a dry run mode
    ```
    docker compose -f docker-compose.ssl.yaml run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --dry-run -d example.com
    ```
- If there are no error, proceed with the same command but this time without the `--dry-run`
- The SSL certificates will be saved inside `certbot/conf/live/<domain>/...`

If issuance failed, you may want to see the first terminal regarding errors. Chances are:
- Your domain doesn't correctly point to your VM's IP
- Domain is pointed correctly, but VM has firewall on port `80`
- ACME failed or reverse proxy failed fue to `nginx` container not running

### Manually renewing the certificate
- Make sure that `nginx` and `certbot` container are running
- You may want to review currently installed certificates

```
docker compose -f docker-compose.ssl.yaml run --rm certbot certificates
```

- Attempt SSL renewal

```
docker compose -f docker-compose.production.yaml run --rm certbot renew [--dry-run]
```

Note: certbot only issue renewal on the last one third of a certificate's lifetime,
so running the renewal command on a fresh certificate won't likely hit the rate limit policy.


- Reloading the `nginx` container for certificate change
The new certificate will not be served before nginx is restarted. 
- To restart nginx without down time, use:

```
docker exec nginx service nginx reload
```



### Automate certificate renewal with cronjob
- Open crontab as root on your host (server/VM)
  ```
  crontab -e
  ```
  - Add this line

  ```
  0 0 15 * * cd <path to this repo> && bash certbot_renewal.sh >> /var/log/moodle-cron-ssl.log 2>&1
  ```

  - It will run every 15 days
  - The cronjob log can be inspected at `/var/log/moodle-cron-ssl.log`


### Monitoring, Migration and Maintenance

#### Files mirroring
Sometimes we need to make an exact duplication (mirror) of all moodle files across different host server. 


```
rsync -Wav --progress old_vm:/home/moodle/ new_vm:/home/moodle/
```

This command is useful to preserve the exact file.

For example: certbot files needs to be formatted as symlinks, and normal scp or rsync will break this.


#### Useful References
- Official documentation
  - Enabling cron: [link](https://docs.moodle.org/405/en/Cron) [link2](https://forums.docker.com/t/cron-does-not-run-in-a-php-docker-container/103897)
  - Customize front page: [link](https://docs.moodle.org/405/en/Change_your_front_page)
  - Enable user sign-up: [link](https://docs.moodle.org/405/en/Enable_sign_up)
  - Enabling email: [link](https://docs.moodle.org/405/en/Mail_configuration)
  - Logging and Monitoring: [link](https://docs.moodle.org/405/en/Cron#:~:text=monitor%20the%20output.-,Logging%20and%20monitoring,-Ideally%20you%20should)
- Other tutorials
  - [How to Set Up letsencrypt with Nginx on Docker](https://phoenixnap.com/kb/letsencrypt-docker)
  - [Installing Postgreqsql 16 client for backup and restore on Ubuntu](https://dev.to/johndotowl/postgresql-16-installation-on-ubuntu-2204-51ia)
  - [How to install moodle on ubuntu 20.04](https://www.howtoforge.com/how-to-install-moodle-on-ubuntu-20-04/)
  - [How to install moodle on ubuntu 22.04](https://www.howtoforge.com/how-to-install-moodle-on-ubuntu-22-04/)
- Commands
  - php commands
    - `which php`
    - `php -i`: phpinfo but cli version
    - `php -m`: all installed php modules
    - `php --ini`: all `.ini` files being used on current php instance
