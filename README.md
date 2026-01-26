# On The Weekend

This repository contains the infrastructure code for the "on the weekend" internet radio station, but with a little bit of work it could be used to run your own icecast server in lightsail

## Running your own

- Copy `.env.template` to `.env` and fill in the values
- You will have to modify the profile and region, as well as the instance name and static ip_name in `./radio`
- By default this creates the smallest lightsail instance. You can change what is created in `./radio`
- Make sure your profile has the appropriate permissions to create, modify, and delete lightsail resources
- Make any configuration changes you want in icecast.template.xml
- run `./radio sync` to create/update

## Oracle Cloud Setup

1. Create a VCN (Virtual Cloud Network)
2. Create an Internet Gateway, attach to VCN
3. Add route rule to default route table: destination `0.0.0.0/0` → Internet Gateway
4. Create a public subnet in the VCN
5. Add ingress rules to the subnet's security list:
   - `0.0.0.0/0` TCP port 22 (SSH)
   - `0.0.0.0/0` TCP port 80 (HTTP)
   - `0.0.0.0/0` TCP port 443 (HTTPS)
6. Create a compute instance (Ubuntu) in the public subnet
7. Note the public IP, add to `.env` and your DNS
8. Run `./radio bootstrap`

## Sub Commands

`bootstrap`: Install icecast, caddy, and configure firewall on existing instance via SSH
`sync`: Update icecast config on existing instance via SSH
`create`: Create or update a Lightsail instance (requires AWS credentials)
`delete`: Delete the Lightsail instance (leaves the static IP detached)
`recreate`: Runs delete and then create
