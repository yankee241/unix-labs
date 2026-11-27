FROM alpine:3.20
RUN apk add --no-cache util-linux
COPY script.sh /script.sh
RUN chmod +x /script.sh
CMD ["/script.sh"]
