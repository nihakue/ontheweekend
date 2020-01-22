# On The Weekend

This repository contains the infrastructure code for the "on the weekend" internet radio station, but with a little bit of work it could be used to run your own icecast server in lightsail

## Running your own

- Make sure you have a .env file containing the password
- You will have to modify the profile and region, as well as the instance name and static ip_name in `./radio`
- By default this creates the smallest lightsail instance. You can change what is created in `./radio`
- Make sure your profile has the appropriate permissions to create, modify, and delete lightsail resources
- Make any configuration changes you want in icecast.template.xml
- run `./radio sync` to create/update

## Sub Commands

`sync`: Create or update your instance (for example if you make a change to icecast.template.xml)
`delete`: Deletes the instance (leaves the static IP in a detached state)
`recreate`: Runs delete and then sync
