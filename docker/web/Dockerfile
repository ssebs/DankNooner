# html/ is the unzipped DankNoonerWeb export, filled in by CI
FROM nginx
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
COPY ./html /usr/share/nginx/html
EXPOSE 8080
