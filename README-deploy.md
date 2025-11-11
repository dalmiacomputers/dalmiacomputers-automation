# README-deploy.md

1) Add GitHub repo - either create new or use existing remote.
2) Add Secrets (see below) in repository Settings -> Secrets & variables -> Actions.
3) Choose FTP-only or SSH workflow by enabling secrets and pushing to main.

Secrets to add for FTP option:
- FTP_HOST: 107.180.113.63
- FTP_USER: your ftp user (e.g. e5khdkcsrpke)
- FTP_PASSWORD: your ftp password
- FTP_REMOTE_ROOT: /public_html
- SITE_DOMAIN: dalmiacomputers.in

Secrets to add for SSH option:
- SSH_PRIVATE_KEY: (the private key contents)
- SSH_HOST: 107.180.113.63
- SSH_PORT: 22
- SSH_USER: your ssh user (cPanel user)
- REMOTE_ROOT: /public_html
- SITE_DOMAIN: dalmiacomputers.in

To set secrets with GitHub CLI (example):
gh secret set FTP_PASSWORD --body "<value>"
