# cloud-1
A project to learn about cloud computing, where I deploy a full stack auto scaling, fault tolerant database and web app with a CDN using AWS and ansible.

# /dev/log for cloud-1 (1st attempt)

[TOC]

# Week 1
## Sandbox provisioning
One of the tools that was suggested is Ansible, which is an automation tool (something like a remote command executor). Like any other new tech that invovles infra, I made a virtual machine as a sandbox to experiment with it.

I also found this [book](https://github.com/GeorgeQLe/Textbooks-and-Papers/blob/master/%5BAnsible%5D%20ansible-up-running-2nd.pdf) which I will be using as my guide.

![](https://hackmd.io/_uploads/BkEVlBiR3.png)

I also installed ansible according to the book, which this command handled everything for us 

`sudo pip install ansible`

The only prerequisite was python and pip.

## Vagrant (server) setup
To have something to act as my "server" to deploy applications on, the guide suggested that we use vagrant as a starter, and so I did. Too bad the book was abiut outdated on the versioning and I had to improvise some bits myself.

![](https://hackmd.io/_uploads/HJz4WBjR2.png)

We did have the vm running and we are able to ssh it. It is important to know the SSH credentials because it will be used by ansible to access the machines. Here are the SSH credentials that I have obtained

![](https://hackmd.io/_uploads/Sk8cWBoRn.png)

Before we are able to test the connectivity between ansible and our VM or any server, we need to first let ansible know about our server. We can do that by creating an inventory file

![](https://hackmd.io/_uploads/S1wmGHiR3.png)

The first file is the hosts file, which defines the hostnames as well as the SSH credentials. The second file is the config file, which tells ansible how to behave.

Once everything seems good, we can use this to test the connectivity.

![](https://hackmd.io/_uploads/HJjtMBo03.png)

## Writing a playbook
So now that my ansible instance can connect to my vm, its time to use that connection to do some actual commands. With that said, we define the imperative instructions using a yaml file, which follows a certian format that constitites it as a playbook.

![](https://hackmd.io/_uploads/SyOk7BiCh.png)

Here, the ansible will SSH into every machine in group webservers and then install and configure nginx using builtin ansible modules. To run this playbook use the command `ansible-playbook playbook.yml`.

Once the command completes, you should be able to access the webpage on localhost
![](https://hackmd.io/_uploads/rJfsXHiR3.png)

## TLS configuration
To support http in production, we would need to buy a certificate from a certificate authority. For dev, we can generate our own using lets encrypt. I ran the commands 

```bash=
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
 -subj /CN=localhost \
 -keyout files/nginx.key -out files/nginx.crt
```

To generate a new SSL cert, and changed the playbook to 

```
---
- name: Configure webserver with nginx and tls
  hosts: webservers
  become: True
  vars:
    key_file: /etc/nginx/ssl/nginx.key
    cert_file: /etc/nginx/ssl/nginx.crt
    conf_file: /etc/nginx/sites-available/default
    server_name: localhost
  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        update_cache: yes
        cache_valid_time: 3600

    - name: Create directories for ssl certificates
      ansible.builtin.file:
        path: /etc/nginx/ssl
        state: directory

    - name: Copy TLS key
      ansible.builtin.copy:
        src: files/nginx.key
        dest: "{{ key_file }}"
        owner: root
        mode: '0600'
      notify: restart nginx

    - name: Copy TLS certificate
      ansible.builtin.copy:
        src: files/nginx.crt
        dest: "{{ cert_file }}"
      notify: restart nginx

    - name: Copy nginx config file
      ansible.builtin.template:
        src: templates/nginx.conf.j2
        dest: "{{ conf_file }}"
      notify: restart nginx

    - name: Enable configuration
      ansible.builtin.file:
        dest: /etc/nginx/sites-enabled/default
        src: "{{ conf_file }}"
        state: link
      notify: restart nginx

    - name: Copy index.html
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /usr/share/nginx/html/index.html
        mode: '0644'

  handlers:
    - name: restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
```
which unlocks a lot of new features such as handlers, templating, facts variables and so on... At this point, we should be able to connect to our website after this in HTTPS.

![](https://hackmd.io/_uploads/r1KcNSiC3.png)
And there we go

# Week 2
## Requirement gathering and Planning of infrastructure
According to the subject, we have gathered the requirements such that we need to have

- High frontend server avaiability
    - Fault tolerance
    - Load balance and autoscaled
    - CDN
- Database and data persistence
    - Data survives container restarts
    - Data survives machine destruction
    - Automated backup / snapshots ?
- Firewall to allow only my IP to SSH
- Phpmyadmin container needs to be installed on frontend server or standalone server
- `docker-compose` to contain all containers build instrctions
- TLS support (LetsEncrypt in wordpress or Nginx wrapper ?)
- Ansible playbook to redeploy containers (I dont think this is needed)

I dont know if thats correct, but theres only 1 way to find out I guess

## Solution discovery
There are many cloud providers out there which can do this for free, with the most notorious ones begin AWS and GCP. No azure because its windows based and no scaleway because im not french.

After [comparing](https://www.codeinwp.com/blog/google-cloud-vs-aws/) the free tier plans, i noticed that GCP has more flexibilty but less features than AWS. Since this is a short term project, I gave AWS the edge since flexibilty isnt going to give me an advantage if I dont plan to maintain my project or scale it further.

We need something to host our containers, so I plan to use the [EC2 instances](https://aws.amazon.com/ec2/instance-types/) for general purpose computing to host the containers.

For load balancing with auto-scaling, we can use [ELB](https://docs.aws.amazon.com/autoscaling/ec2/userguide/autoscaling-load-balancer.html) to provide the routing logic to a [EC2 auto scaling](https://aws.amazon.com/ec2/autoscaling/getting-started/) resource.

For CDN, AWS has [CloudFront](https://aws.amazon.com/cloudfront/) which is needed to improve load times of static files and have security features suck as AWS shield standard and WAF.

To make sure I dont have any data loss, I will store my data for MySQL in an [EBS Volume](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volumes.html) which is isolated from the EC2 instances and it is recoverable after the EC2 instance is destroyed.

My initial plan is like so
![](https://hackmd.io/_uploads/SyDpecaA3.png)

## DB instance creation
While creating your first EC2 instance, you need to create a new key pair to be able to SSH into it. Here it is on the EC2 instance creation screen

![](https://hackmd.io/_uploads/rJOb1RpC2.png)

For now, Im going to allow internet access to the SSH port for debugging. In production, this will live inside a VPC and will only be exposed to the frontend servers.

I am able to SSH into the DB instance using the command 
`ssh -i ssh/jng.pem ec2-user@ec2-52-64-169-82.ap-southeast-2.compute.amazonaws.com` where `ssh/jng.pem` is the private key i get from the AWS console when I create a new key pair. 

>However, the VM is barren currently, No git or docker, only yum and python3. This might be a good time to write an ansible playbook to bootstrap the EC2 instance.

## Playbook to bootstrap the database EC2 instance
I need to create a host file to tell ansible which server to connect to, the contents are below

```
[database]
dbserver ansible_host=<REDACTED> ansible_user=ec2-user ansible_private_key_file=../ssh/jng.pem
```

I also made an ansible.cfg to provide context to the ansible application

```
[defaults]
inventory = ./dbhosts
host_key_checking = False
```

> Sanity check to test connectivity `ansible database -m ping`

Create a playbook with the contents
```yaml
# playbooks/bootstrap.yaml
---
- name: Bootstrap a database EC2 instance
  hosts: database
  become: True
  
  tasks:
    - name: Install Git package
      yum:
        name: git
        state: present
```

To run the playbook, run `ansible-playbook playbooks/bootstrap.yaml`

After running, you can SSH into the machine manually to verify that git is indeed installed

![](https://hackmd.io/_uploads/S13KUR6A2.png)

I proceeded to write a docker-compose.yml with the instructions to start a Mysql container

```yaml
version: "3.9"
services:
  mysql:
    image: mysql:latest
    volumes:
      - ./mysql_data:/var/lib/mysql # change this to EBS soon
    environment:
      - MYSQL_ROOT_PASSWORD=password
```

and I modified the playbook to install docker, docker compose and to run the container

```yaml
# playbooks/bootstrap-db.yaml
---
- name: Bootstrap a database EC2 instance
  hosts: database
  become: True
  
  tasks:
    - name: Install Git package
      yum:
        name: git
        state: present

    - name: Install Docker package
      yum:
        name: docker
        state: present

    - name: Run and enable docker
      service:
        name: docker
        state: started
        enabled: true

    - name: Install or upgrade docker-compose
      get_url:
        url: "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64"
        dest: /usr/local/bin/docker-compose
        mode: 'a+x'
        force: yes
      when: docker_compose_current_version is not defined or docker_compose_current_version is version(docker_compose_version, '<')

    - name: Clone repo with build instructions
      git:
        repo: https://github.com/neosizzle/cloud-1.git
        dest: /home/ec2-user/cloud-1
        clone: yes
        update: yes

    - name: Creates mysql data directory
      file:
        path: /home/ec2-user/cloud-1/docker/mysql_data
        state: directory

    - name: Run docker-compose up on docker/docker-compose.yml
      command: docker-compose up -d mysql
      args:
        chdir: /home/ec2-user/cloud-1/docker

```


And now we should be able to see the container running in the EC2 instance
![](https://hackmd.io/_uploads/Bk04X1AA3.png)

## Auto backup 
To simulate a hardware failure, lets make the instance inaccesible by disabling its network interface `sudo ifconfig enX0 down`

Now to make sure this incident gets detected, we can use CloudWatch to monitor the EC2 instance status and generate alerts if something is not right (in this case our instance is unreachable)

![](https://hackmd.io/_uploads/H15y1kGya.png)

With this in place, we should now create a task to run once an alert appears. To take care of the first part `create a task to run`, we are able to use [Lambda functions](https://www.serverless.com/aws-lambda), which are code that runs on the cloud which are triggered by events happening in your infra, which is the second part (once an alert appears).

Here is an example of a bootstrap lambda function, which just prints hello world for the time being. I want to configure this to run once an alert is generated by my CloudWatch. 
![](https://hackmd.io/_uploads/Sk8x-Jf1T.png)

To make my cloudwatch events detected by the lambda function, I need to make an eventbridge where the source is cloudwatch and the target is the lambda function I made.
![](https://hackmd.io/_uploads/BJ-GEyM1T.png)

And once the two is ready, I added that eventbridge as a trigger to my lambda function
![](https://hackmd.io/_uploads/Hy-Rm1G16.png)

Lets goo, looks like I got a hit
![](https://hackmd.io/_uploads/B190vJMkT.png)

## Fuckup 1
You cant have an alarm for multiple instances together, which means everytime a new instance is created a new alarm must be created. This is tedious. Im just going to reboot the instance on fail instead.

And as we can see, the error state resolved itself
![](https://hackmd.io/_uploads/H1Zv8OMyT.png)

And the database container started up.
![](https://hackmd.io/_uploads/ByuOIOfya.png)


## phpmyadmin and Security groups
So now we will create an EC2 instance to run phpmyadmin, with the compose file below

```yaml=
# ...
phpmyadmin:
    image: phpmyadmin/phpmyadmin
    environment:
      PMA_HOST: 172.31.0.82 # Put the private ip address for the db instance here
      PMA_PORT: 3306
      PMA_USER: root
      PMA_PASSWORD: password
    ports:
      - 80:80
    volumes:
      - /sessions
    restart: always
```

We will also create an ansible playbook to automate the provisioning of the instance, with the contents below
```yaml=
# playbooks/bootstrap-phpmyadmin.yaml
---
- name: Bootstrap a phpmyadmin EC2 instance
  hosts: phpmyadmin
  become: True
  
  tasks:
    - name: Install Git package
      yum:
        name: git
        state: present

    - name: Install Docker package
      yum:
        name: docker
        state: present

    - name: Run and enable docker
      service:
        name: docker
        state: started
        enabled: true

    - name: Install or upgrade docker-compose
      get_url:
        url: "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64"
        dest: /usr/local/bin/docker-compose
        mode: 'a+x'
        force: yes
      when: docker_compose_current_version is not defined or docker_compose_current_version is version(docker_compose_version, '<')

    - name: Clone repo with build instructions
      git:
        repo: https://github.com/neosizzle/cloud-1.git
        dest: /home/ec2-user/cloud-1
        clone: yes
        update: yes

    - name: Run docker-compose up on docker/docker-compose.yml
      command: docker-compose up -d phpmyadmin
      args:
        chdir: /home/ec2-user/cloud-1/docker

```

When all is said and done, we should be able to connect to the public IP of the phpmyadmin instance

![](https://hackmd.io/_uploads/ByNdROfJp.png)

And as we might have noticed, there seems to be an error with the configuration for the mysql server connectivity. This is becase we are trying to connect to our database instance at `172.31.0.82` which is not exposed to other instances.

![](https://hackmd.io/_uploads/BJOgwtf1T.png)

After I added the rule to allow the phpmyadmin instance, I should be able to view the data now.

![](https://hackmd.io/_uploads/S12zDtfkp.png)

## Wordpress
This is getting abit repetitive, we will create a docker-compose section and an ansible playbook to provision a wordpress container.

There will be new directories created : 
- `./ngninx.conf` will contain the files needed for our nginx webserver configuration
- `./ssl` will contain our self-signed ssl credentials
- `./wordpress_data` will contain wordpress installation files

```yaml=
# docker-compose.yml
# ---
  wordpress:
    image: wordpress:latest
    volumes:
      - ./wordpress_data:/var/www/html # change this to EBS soon
    environment:
      WORDPRESS_DB_HOST: 172.31.0.82:3306 # Put the private ip address for the db instance here
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpresspassword
      WORDPRESS_DB_NAME: wordpress

  webserver:
    depends_on:
      - wordpress
    image: nginx:latest
    volumes:
      - ./wordpress_data:/var/www/html
      - ./nginx-conf:/etc/nginx/conf.d
      - ./ssl:/etc/nginx/ssl
    ports:
      - "80:80"
      - "443:443"
```

```yaml=
# playbooks/bootstrap-wp.yaml
---
- name: Bootstrap a wordpress EC2 instance
  hosts: wp
  become: True
  
  tasks:
    - name: Install Git package
      yum:
        name: git
        state: present

    - name: Install Docker package
      yum:
        name: docker
        state: present

    - name: Run and enable docker
      service:
        name: docker
        state: started
        enabled: true

    - name: Install or upgrade docker-compose
      get_url:
        url: "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64"
        dest: /usr/local/bin/docker-compose
        mode: 'a+x'
        force: yes
      when: docker_compose_current_version is not defined or docker_compose_current_version is version(docker_compose_version, '<')

    - name: Clone repo with build instructions
      git:
        repo: https://github.com/neosizzle/cloud-1.git
        dest: /home/ec2-user/cloud-1
        clone: yes
        update: yes

    - name: Creates wordpress_data directory
      file:
        path: /home/ec2-user/cloud-1/docker/wordpress_data
        state: directory

    - name: Creates ssl directory
      file:
        path: /home/ec2-user/cloud-1/docker/ssl
        state: directory

    - name: Run command to generate self signed cert
      command: openssl req -x509 -newkey rsa:4096 -nodes -out cert.pem -keyout key.pem -days 365
      args:
        chdir: /home/ec2-user/cloud-1/docker/ssl

    - name: Run docker-compose up on docker/docker-compose.yml
      command: docker-compose up -d wordpress webserver
      args:
        chdir: /home/ec2-user/cloud-1/docker

```

```nginx=
# docker/nginx-conf/default.conf
server {
    listen 80;
    server_name _; # public ip of wordpress server

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name _; # public ip of wordpress server

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    location / {
        proxy_pass http://wordpress;
    }
}

```

> Of course, dont forget to change the security group for the database instance to allow your wordpress to connect

And with the configuration above, we get these
![](https://hackmd.io/_uploads/BkS-e0f16.png)

This isnt exactly correct, since the CSS should be loaded as well. Upon inspecting the network tab, turns out there are some hostname errors

![](https://hackmd.io/_uploads/rJbNgCMya.png)

Our nginx server just reverse-proxies all request to the wordpress container. While the nginx container itself knows where to route to, the client does not. Hence we are unable to get things like fonts and CSS.

Then I remembered for our inception project, we copied the pre-installed files into nginxs static folder, and we would just use that as the root instead.

For the php files, we will route it to wordpresses fpm as a CGI controller.

Hence, we will change our docker-compose like so:
```yaml=
# ...
wordpress:
    image: wordpress:php8.2-fpm
    volumes:
      - ./wordpress_data:/var/www/html # change this to EBS soon
    environment:
      WORDPRESS_DB_HOST: 172.31.0.82:3306 # Put the private ip address for the db instance here
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpresspassword
      WORDPRESS_DB_NAME: wordpress
    restart: always
```
which only exposes the CGI application at port 9000. We will handle the static files on nginx side. We change the nginx config to : 

```nginx=
# docker/nginx-conf/default.conf
server {
    listen 80;
    server_name _; # public ip of wordpress server

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name _; # public ip of wordpress server

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

  	root /var/www/html/;
	
	# declare index files to serve
    index index.html index.htm index.nginx-debian.html index.php;

	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files $uri $uri/ =404;
    }

	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)$; #regex to split path route
		fastcgi_pass wordpress:9000; #proxy to fastcgi server running on another container
		fastcgi_index index.php; #index file to server
		include fastcgi_params; #include other vital default fastcgi parameters
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; #path on container to obtain all php scripts
		fastcgi_param PATH_INFO $fastcgi_path_info; #another vital fastcgi param which i have no idea what it is yet
    }

}

```

And viola, looks better now

![](https://hackmd.io/_uploads/HJwn-Azyp.png)
![](https://hackmd.io/_uploads/S1s-GRMJT.png)

## Autoscaling and load balancing
Before we create an autoscaling groupm a [Launch template](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-templates.html) needs to be made to tell new ec2 instances how to provision themselves. 

They consist of just the initial configuration of the ec2 instance (OS to use, security rules) and a userdata script. The userdata script is a shell script that in run as root to install and run stuff.

The user data script that I used for my launch template is : 
```bash=
#!/bin/bash

# Update the instance and install Docker
yum update -y
yum install -y git docker

# Start and enable Docker service
service docker start
chkconfig docker on

# Install Docker Compose dependencies
yum install -y gcc libffi-devel python3-devel openssl-devel libxcrypt-compat

# Install libcrypt package
yum install -y libcrypt

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone the repository
git clone https://github.com/neosizzle/cloud-1.git /home/ec2-user/cloud-1

# Create necessary directories
mkdir /home/ec2-user/cloud-1/docker/wordpress_data
mkdir /home/ec2-user/cloud-1/docker/ssl

# Generate SSL certificate
cd /home/ec2-user/cloud-1/docker/ssl
openssl req -x509 -nodes -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -subj "/C=MY/ST=Selangor/L=Kuala Lumpur"

# Start Docker Compose
cd /home/ec2-user/cloud-1/docker
docker-compose down
docker-compose up -d wordpress webserver
```

I launch a test ec2 instance and got it to work, but its not detecting any sessions because of the abscence of load balancing and domain name

![](https://hackmd.io/_uploads/SJ_AJeX1T.png)

To get it to work, I have to create an auto scaling group that specifies the minimum instances I want. It also creates a Target Group to group all our aws instances to specify the routed destinations (port 443 of those instances)

![](https://hackmd.io/_uploads/B1eVExXXka.png)

Then, I will need to make 2 Load balancers for HTTP and HTTPS traffic. The HTTP load balancer will redirect to the HTTPS load balancer and the HTTPS load balancer shall distribute traffic to the target group.


![](https://hackmd.io/_uploads/HkpEWXXJT.png)



Then, I would need to create a default  SSL certificate key pair for the loadbalancers that are listening on https using `openssl req -x509 -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 ` and then register them to ACM

![](https://hackmd.io/_uploads/ByIigmXya.png)

Everything looks OK, just that for some reason my wordpress cant access wp-admin, and just redirects me to the login page even after successful login. I suspect its something to do with my nginx

I applied the fix like so, its also a good time to test the auto scaling feature now.

```nginx=
# docker/nginx-conf/default.conf
server {
    listen 80;
    server_name _; # public ip of wordpress server

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name _; # public ip of wordpress server

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

  	root /var/www/html/;
	
	# declare index files to serve
    index index.html index.htm index.nginx-debian.html index.php;

	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files $uri $uri/ =404;
    }

	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)$; #regex to split path route
		fastcgi_pass wordpress:9000; #proxy to fastcgi server running on another container
		fastcgi_index index.php; #index file to server
		include fastcgi_params; #include other vital default fastcgi parameters
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; #path on container to obtain all php scripts
		fastcgi_param PATH_INFO $fastcgi_path_info; #another vital fastcgi param which i have no idea what it is yet
        fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info; # I was missing this param
    }

}

```

Actually it was not fixed until I enabled this option in my target group settings
![](https://hackmd.io/_uploads/BJosSPHJa.png)


And turns out my instances gets created if i stop them and the target group auto updates, which is nice.

![](https://hackmd.io/_uploads/Hy-WDCM1a.png)
![](https://hackmd.io/_uploads/SJlpMw0f16.png)
![](https://hackmd.io/_uploads/BkIEPAGkT.png)
![](https://hackmd.io/_uploads/S1MHPAG1T.png)

## Auto scaling and Load balancing verification
To test the load balancing feature, I will display the docker logs for nginx containers side by side and make sure both of them are getting hits when I made a request to the load balancers DNS.

As you can see, both the servers get hits when i make a request, hence validating the load balancer.

[demo here](https://www.youtube.com/watch?v=Wa4S5CcZboY)
{%youtube Wa4S5CcZboY %}

I also made an alarm to alert the system when any of the EC2 instances in the auto scale is down and added a dynamic scaling policy which is triggered by the alart. Here are the activity logs to show that its working

![](https://hackmd.io/_uploads/ryl0yF416.png)


## Notifications
I created an SNS topic to allow my infra to send out emails, and I attatched it to the CloudWatch Alarm like so

![](https://hackmd.io/_uploads/B1VQfF41a.png)

And once an instance fails, here is the email
![](https://hackmd.io/_uploads/BkOgOKVya.png)

# Week 3

## CDN
I set up AWS Cloudfront to act as a CDN to my system. 

I also installed WAF on cloudfront with default settings which by alone does not do anything, however if properly configured with other services like AWS shield, it can protect against common attacks like [DDOS, SQL Injection, XSS](https://repost.aws/knowledge-center/waf-rule-prevent-sqli-xss) and much more.

![](https://hackmd.io/_uploads/Sk12WQB1T.png)
This is unfortunate, I guess ill need to reach out to support for this matter. Guess Ill have to wait for now.

Solved within 2 hours, but I reread the pdf and found out i might not need it lol

## Security
I have changed all the SSH rules to only allow my own IP, and that should be it.

## Cost containment
![](https://hackmd.io/_uploads/BymPTDBJT.png)
