# Cloudflare 

## Cloudflare/cf-phpfpm-attack-toggle.sh

### How to setup the API Key in Cloudflare
To generate the API key in cloudflare, you will need to go to

Manage Account -> Account API Tokens -> Create Token

Make sure to select Zone -> Zone Settings both (Edit/Read)

Add a Cronjob to use:
	
	 * * * * * bash /path/to/script/cf-phpfpm-attack-toggle.sh >> /var/log/cf-under-attack.log

## Cloudflare/cf_uam.sh
Script used to check the status/enable/disable under attack mode (uam)

	$ bash ./cf_uam.sh -h
	Usage: ./cf_uam.sh {status|enable|disable}
