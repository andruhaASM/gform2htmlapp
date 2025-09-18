FROM --platform=linux/amd64 perl:5.36-slim

WORKDIR /app

COPY . /app
ADD templates /opt/templates

RUN cpanm Mojolicious

ENV PORT=8080
ENV MOJO_LISTEN=http://*:$PORT

EXPOSE 8080

CMD ["hypnotoad", "-f", "gform2htmlapp.pl"]

