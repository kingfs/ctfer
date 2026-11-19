# Fingerprints — common products, default paths and default credentials

Use this as a starting point, **not as proof**. Confirm with a version banner,
a response body, or an actual file read. Default credentials are only worth
trying once you have identified the product and version.

## Nginx / Apache / Tomcat

- Nginx status: `/nginx_status`, `/status`
- Apache status: `/server-status`, `/server-info`
- Tomcat manager: `/manager/html`, `/host-manager/html`
- Tomcat examples: `/examples/`, `/docs/`
- Tomcat default credentials: `tomcat:s3cret`, `admin:admin`,
  `manager:manager`, `role1:role1`
- Spring Boot Actuator: `/actuator`, `/actuator/env`, `/actuator/heapdump`,
  `/actuator/mappings`, `/actuator/health`

## Gradio / Streamlit / ML demos

- Gradio UI: `/`; config: `/config`, `/info`
- Gradio queue: `/queue/join`, `/api/predict`, `/run/predict`
- Gradio file read patterns: `/file=<path>`, `/file=../...` (test carefully)
- Older Gradio has no auth; `/config` leaks component metadata and dependencies
- Streamlit: `/_stcore/health`, `/static/`

## Next.js / Node front ends

- Build assets: `/_next/static/`
- Image optimizer: `/_next/image?url=...` (open redirect / SSRF depending on version)
- API routes: `/api/...`
- Build manifest: `/_next/static/<buildId>/_buildManifest.js`
- Source maps: `*.js.map` — check before anything else, they often ship the source

## Java / middleware

- Jolokia: `/jolokia/`, `/jolokia/exec/...`
- WebLogic: `/console`, `/wls-wsat/CoordinatorPortType`
- JBoss: `/jmx-console/`, `/web-console/`
- Struts: `*.action`, `*.do`
- Fastjson / Jackson: look for JSON endpoints accepting `@type` / `@class`

## PHP

- phpinfo: `/phpinfo.php`, `/info.php`, `/test.php`
- Laravel: `/.env`, `/storage/logs/laravel.log`, `/_ignition/health-check`
- ThinkPHP: `/index.php?s=...`, `/?s=...`
- LFI candidates: `?file=`, `?page=`, `?path=`, `?include=`, `?template=`

## Common leak files

```
/.git/config          /.git/HEAD
/.svn/entries         /.DS_Store
/.env                 /.env.bak
/backup.zip           /www.zip          /web.zip
/config.php.bak       /index.php.bak
/robots.txt           /sitemap.xml
/Dockerfile           /docker-compose.yml
/package.json         /composer.json
```

## Backup / archive naming

`www`, `web`, `backup`, `bak`, `db`, `sql`, `site`, `html`, `source`, `src`,
`code` combined with `.zip`, `.tar.gz`, `.rar`, `.7z`, `.sql`, `.bak`, `.old`,
`.swp`, and a date suffix (`2024`, `20240101`).

## Cloud / object storage

- S3-style list: `?list-type=2&prefix=`
- MinIO console: `/minio/`, `/minio/health/live`
- Alibaba OSS / Tencent COS: XML listing with `<ListBucketResult>`
- Metadata endpoints (SSRF): `169.254.169.254`, `metadata.google.internal`,
  `100.100.100.200` (Alibaba)

## Kubernetes / container

- API: `/api/v1/namespaces`, `/apis`, `/version`
- kubelet: `:10250/pods`, `:10250/run/<ns>/<pod>/<container>`
- Service account token: `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Docker socket: `/var/run/docker.sock`

## Redis / databases

- Redis unauthenticated: `redis-cli -h <host> ping` → `PONG`
- MySQL default: `root:` (empty), `root:root`, `root:password`
- MSSQL: `sa:` (empty) is still seen in old images
- MongoDB: no auth on 27017 → `show dbs`

## Methodology reminders

1. **Version first.** A banner (or `/package.json`, `Server:` header, favicon
   hash) narrows the CVE list far more than blind fuzzing.
2. **Read before you exploit.** Try source maps, `.git`, Actuator, Gradio
   `/config` — leaked source turns a black-box challenge into a white-box one.
3. **One hypothesis per request.** Change one parameter at a time and keep the
   raw request/response; agents must not "remember" a response they never saw.
