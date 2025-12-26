**FIX n8n v2.0 Execute Commands on N8n Self Hosted**

![][image1]

If you just updated to n8n v2.0 but your entire workflow is broken.

I’ll show you how to get it fixed in just 1 line. 

From Upgrading to 2.0 if you don’t have that to making the Execute Command work and the “Write File” cuss that may be broken as well.. 

So let’s get started with 

### **How to update to n8n 2.0 Self Hosted With FFMPEG**

([Link](?tab=t.6yrnzamzjvur))

### **Changes to make Execute Command Work:** 

environment:  
  \- N8N\_ALLOW\_EXECUTE\_COMMAND=true  
  \- N8N\_ENABLE\_NODE\_DEV=true  
  \- NODES\_EXCLUDE=\[\]  
  \- N8N\_FILESYSTEM\_PATH\_WHITELIST=/videos

### **File Read / Write** 

Volumes:  
\- n8n\_data:/home/node/.n8n  
\- ./videos:/home/node/.n8n-files

Inside n8n node write file:  
/home/node/.n8n-files/

### **Chown & Chmod**

sudo chown \-R 1000:1000 ./videos  
sudo chmod \-R 755 ./videos

(some also may need)   
sudo chmod \-R 777 ./videos

### **Restart**

docker compose down  
docker compose up \-d

My ChatGPT Chat: ([LINK](https://chatgpt.com/share/694392a9-44a4-8000-a0de-1c3ab5902a3e))  
Read it from the beginning to see how i came to this

### **TOGGLE (my docker-compose.yml v1.9)** 

version: "3.7"

services:  
  traefik:  
    image: "traefik"  
    restart: always  
    command:  
      \- "--api=true"  
      \- "--api.insecure=true"  
      \- "--providers.docker=true"  
      \- "--providers.docker.exposedbydefault=false"  
      \- "--entrypoints.web.address=:80"  
      \- "--entrypoints.web.http.redirections.entryPoint.to=websecure"  
      \- "--entrypoints.web.http.redirections.entrypoint.scheme=https"  
      \- "--entrypoints.websecure.address=:443"  
      \- "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"  
      \- "--certificatesresolvers.mytlschallenge.acme.email=${SSL\_EMAIL}"  
      \- "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"  
    ports:  
      \- "80:80"  
      \- "443:443"  
    volumes:  
      \- traefik\_data:/letsencrypt  
      \- /var/run/docker.sock:/var/run/docker.sock:ro

  n8n:  
    image: n8n-with-ffmpeg:latest  
    restart: always  
    ports:  
      \- "127.0.0.1:5678:5678"  
    labels:  
      \- traefik.enable=true  
      \- traefik.http.routers.n8n.rule=Host(\`${SUBDOMAIN}.${DOMAIN\_NAME}\`)  
      \- traefik.http.routers.n8n.tls=true  
      \- traefik.http.routers.n8n.entrypoints=websecure  
      \- traefik.http.routers.n8n.tls.certresolver=mytlschallenge

      \- traefik.http.middlewares.n8n.headers.SSLRedirect=true  
      \- traefik.http.middlewares.n8n.headers.STSSeconds=315360000  
      \- traefik.http.middlewares.n8n.headers.browserXSSFilter=true  
      \- traefik.http.middlewares.n8n.headers.contentTypeNosniff=true  
      \- traefik.http.middlewares.n8n.headers.forceSTSHeader=true  
      \- traefik.http.middlewares.n8n.headers.SSLHost=${DOMAIN\_NAME}  
      \- traefik.http.middlewares.n8n.headers.STSIncludeSubdomains=true  
      \- traefik.http.middlewares.n8n.headers.STSPreload=true

      \- traefik.http.routers.n8n.middlewares=n8n@docker,n8n-nobuffer@docker  
      \- traefik.http.middlewares.n8n-nobuffer.headers.customResponseHeaders.X-Accel-Buffering=no

    environment:  
      \- N8N\_HOST=${SUBDOMAIN}.${DOMAIN\_NAME}  
      \- N8N\_PORT=5678  
      \- N8N\_PROTOCOL=https  
      \- NODE\_ENV=production  
      \- WEBHOOK\_URL=https://${SUBDOMAIN}.${DOMAIN\_NAME}/  
      \- GENERIC\_TIMEZONE=${GENERIC\_TIMEZONE}  
      \- N8N\_DEFAULT\_BINARY\_DATA\_MODE=filesystem  
      \- N8N\_TRUSTED\_PROXIES=true  
      \- N8N\_ALLOW\_EXECUTE\_COMMAND=true  
      \- N8N\_ENABLE\_NODE\_DEV=true  
      \- NODES\_EXCLUDE=\[\]  
      \- N8N\_FILESYSTEM\_PATH\_WHITELIST=/videos

    volumes:  
      \- n8n\_data:/home/node/.n8n  
      \- ./videos:/home/node/.n8n-files  
      \- /local-files:/files  
      \- ./videos:/videos  
      \- /usr/share/fonts:/usr/share/fonts

volumes:  
  traefik\_data:  
    external: true  
  n8n\_data:  
    external: true  


[image1]: <data:image/png;base64,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6iNgbBAwCRAw1UfA2CBgEiBgqo+AsUHAJEDAVB8BY4OASYCAqT4CxgYBkwABU30EjA0CJgECpvoIGBsETAIETPURMDaCA0YWkpmYmFD1UEuXLs3Wr1+v6qFGR0dVrRHj4+OqFkr6pszqZARM9ZUJmGXLlmWdnZ2qHspqDlvsRxaTs1glUp5P0jfBAYOZI2CqT8ZHAsQfO4QhYBIYGhoiYCps7dq1+fhYLA17piNgEuju7s4n8PLly9XkRnpjY2P5+PjjhnAETCK8TKomWZlfxqWvr0+NGcIRMInICvAykc877zw1yZGOC35/vNAYAiahVatWcSRTEXJC143FggUL1FihMQRMYm5SCzm56E98xCcfl3Bj0NXVpcYIjSNgKkDerSgGDU6/NWvWqHHBzBEwFSPnZuRdpt7eXkTW0dGh+h+2CBgA0RAwAKIhYABEQ8AAiIaAARANAQMgGgIGQDQEDIBoggNGPgi2ceNGVQ8lH3Sy+PSkfPvVrzVi3bp1qhZK+qa/v1/VQ8k3edvb21U9lMU4Catxsugbi1XbrOaw1ThZzWGLcZJVGa3GSfomOGAAoCwCBkA0BIzntttuy06dOjUlf5szlbzMLfbLF198kc2dO1e1g3amzCUCxtNqASP39/jx46o+U36fFH366aeqPf6tGedSIwgYjwuYF154QV3XjGIEjHtyPPvss+q6999//4x58szEmdJHBIwnJGBeeeWVXNn666+/nv3111/Zzp0789+F8q93Lr744uzw4cPZ22+/nd14443q+nr7lye8q9900035324iy9+7du36V/tZs2ZlBw4cyP75559s+/btan+17NixI9/fTz/9pK5zpnry7N+/Pw+8l156SV0nio/N3darr746ef3IyEh+23Kf/T7csGFDvu1FF12Uvxvy2muvZb/88kt2xRVXTLZ54IEH8n1+/9136radW265Jfv666+z77//PrvqqqvU9cX7uHXr1uzzzz/PPvroo7rvTMm7VtL+zz//zJ5//vm8NlUftRICxhMSMBIC0vauu+6arNWaOEeOHJmsF0m92K6trU21cYrLONa6DfHzzz9P1h9//HG1j2Io+Nc5zzzzjNpvUb3bno5/O448kcu0+/HHH7P7779f1f/444/JbS+77LK8dscdd6h2sqiUXxNbtmyZ3F7WR/avd2rdR+lPv50LEOexxx5T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>