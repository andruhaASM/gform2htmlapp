FROM perl:5.42
RUN cpanm Mojolicious
RUN cpanm UUID::Tiny
WORKDIR /opt
COPY gform2htmlapp.pl .
ADD templates /opt/templates
ADD lib /opt/lib
CMD ["perl", "gform2htmlapp.pl", "daemon"]
